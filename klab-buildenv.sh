#!/usr/bin/env bash
set -Eeuo pipefail

# KLAB_UNIFIED_ROOT_R22
# KLAB_NATIVE_PATHS_R23
# KLAB_RESIDUAL_PATH_AUDIT_R24
_KLAB_SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ARCH_MODEL_BIN="${KLAB_ARCH_MODEL_BIN:-$_KLAB_SELF_DIR/lib/arch-model.sh}"
[[ -f "$ARCH_MODEL_BIN" ]] || { echo "klab-buildenv: ERROR: architecture model missing: $ARCH_MODEL_BIN" >&2; exit 1; }
# shellcheck source=lib/arch-model.sh
source "$ARCH_MODEL_BIN"
if [[ -f "$_KLAB_SELF_DIR/lib/klab-root.sh" ]]; then
  # shellcheck source=lib/klab-root.sh
  source "$_KLAB_SELF_DIR/lib/klab-root.sh"
  klab_root_ensure_layout
fi
unset _KLAB_SELF_DIR
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PY="$SELF_DIR/lib/klab_buildenv.py"
TOOLCHAIN_BOUNDARY_BIN="${KLAB_TOOLCHAIN_BOUNDARY_BIN:-$SELF_DIR/klab-toolchain-boundary.sh}"
DISTRO_TOOLCHAIN_BIN="${KLAB_DISTRO_TOOLCHAIN_BIN:-$SELF_DIR/klab-distro-toolchain.sh}"
die(){ printf 'klab-buildenv: ERROR: %s\n' "$*" >&2; exit 1; }
usage(){ cat <<'EOF'
Usage:
  klab-buildenv.sh create --root DIR --provider NAME --release REL --kernel-release KREL \
      --target-arch ARCH --exec-arch ARCH --build-dir RELPATH --package-manifest FILE \
      --installed-inventory FILE --provider-image sha256:... \
      [--dependency-archives DIR --dependency-provenance FILE] \
      [--recipe-version V] [--source-dir RELPATH] [-o FILE.klabbuildenv]
  klab-buildenv.sh verify FILE.klabbuildenv [--deep]
  klab-buildenv.sh inspect FILE.klabbuildenv
  klab-buildenv.sh import FILE.klabbuildenv [--force]
  klab-buildenv.sh lookup SHA256_ID
  klab-buildenv.sh list
  klab-buildenv.sh assert-installed SHA256_ID --provider NAME --release REL --kernel-release KREL --target-arch ARCH [--json]
  klab-buildenv.sh verify-installed SHA256_ID
  klab-buildenv.sh doctor
  klab-buildenv.sh run-module SHA256_ID --toolchain-root DIR --toolchain-cc RELPATH \
      [--cross-prefix RELPREFIX] [--toolchain-tree-sha256 SHA256] [--toolchain-family gcc]
      [--toolchain-version VERSION] [--toolchain-target TRIPLE] --module DIR [--jobs N] [--kernel-arch ARCH]\n      --expect-provider NAME --expect-release REL --expect-kernel-release KREL --expect-target-arch ARCH
  klab-buildenv.sh run-module-native SHA256_ID --distro-toolchain-id SHA256_ID --module DIR [--jobs N] [--kernel-arch ARCH] \
      --expect-provider NAME --expect-release REL --expect-kernel-release KREL --expect-target-arch ARCH
EOF
}
json_get(){ local f="$1" q="$2"; if command -v jq >/dev/null 2>&1; then jq -er "$q" "$f"; else python3 - "$f" "$q" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); q=sys.argv[2].lstrip('.').split('.')
for k in q:
    if k: x=x[k]
print(x if not isinstance(x,(dict,list)) else json.dumps(x,sort_keys=True))
PY
fi; }
canonical_arch(){ local a; a="$(klab_arch_canonical "$1" 2>/dev/null || true)"; [[ -n "$a" ]] || die "unsupported architecture: $1"; echo "$a"; }
karch(){ local a; a="$(canonical_arch "$1")"; klab_arch_kernel_arch "$a" 2>/dev/null || die "architecture $a has no Linux ARCH mapping"; }
host_arch(){ klab_arch_host; }
native_exec_supported(){
  local exec_arch host handler
  exec_arch="$(canonical_arch "$1")"; host="$(host_arch)"
  [[ "$exec_arch" == "$host" ]] && return 0
  case "$exec_arch" in
    aarch64) handler=/proc/sys/fs/binfmt_misc/qemu-aarch64 ;;
    armv7) handler=/proc/sys/fs/binfmt_misc/qemu-arm ;;
    i386) handler=/proc/sys/fs/binfmt_misc/qemu-i386 ;;
    riscv64) handler=/proc/sys/fs/binfmt_misc/qemu-riscv64 ;;
    *) return 1 ;;
  esac
  [[ -r "$handler" ]] || return 1
  grep -qx enabled "$handler" && grep -q '^interpreter ' "$handler" && grep -Eq '^flags:.*F' "$handler"
}
objdir(){ printf '%s/artifacts/buildenvs/sha256/%s\n' "$KLAB_ROOT" "$1"; }
verify_installed(){ local id="$1" o m; o="$(objdir "$id")"; m="$o/manifest.json"; [[ -f "$m" ]] || die "buildenv not installed: $id"; [[ "$(basename "$o")" == "$(json_get "$m" '.id')" ]] || die "buildenv ID/path mismatch"; python3 "$PY" lookup "$id" --home "$KLAB_ROOT" >/dev/null; }
doctor(){ local ok=1; for x in python3 tar zstd sha256sum bwrap; do command -v "$x" >/dev/null || { echo "missing: $x"; ok=0; }; done; if command -v bwrap >/dev/null; then echo "sandbox: bwrap"; else echo "sandbox: missing (buildenv module execution requires bubblewrap/bwrap)"; fi; ((ok==1)); }
real_inside(){ local root="$1" rel="$2" p; [[ "$rel" != /* && "$rel" != *'..'* ]] || return 1; p="$(readlink -f "$root/$rel")" || return 1; case "$p" in "$root"/*) printf '%s\n' "$p";; *) return 1;; esac; }
image_exec_inside(){ python3 - "$1" "$2" <<'PY_IMAGE_EXEC'
import os,pathlib,stat,sys
root=pathlib.Path(sys.argv[1]); raw=sys.argv[2]
if not raw.startswith('/') or '..' in pathlib.PurePosixPath(raw).parts: raise SystemExit(1)
rel=pathlib.PurePosixPath(raw.lstrip('/'))
for _ in range(41):
 p=root/str(rel)
 try: st=os.lstat(p)
 except OSError: raise SystemExit(1)
 if not stat.S_ISLNK(st.st_mode):
  raise SystemExit(0 if stat.S_ISREG(st.st_mode) and stat.S_IMODE(st.st_mode)&0o111 else 1)
 target=os.readlink(p)
 rel=(pathlib.PurePosixPath(target.lstrip('/')) if os.path.isabs(target) else pathlib.PurePosixPath(os.path.normpath(str(rel.parent/target))))
 if '..' in rel.parts: raise SystemExit(1)
raise SystemExit(1)
PY_IMAGE_EXEC
}
run_module(){ local id="$1"; shift; local tcroot='' ccrel='' prefix='' module='' jobs="${KLAB_JOBS:-4}" karch_arg='' tc_tree='' tc_family='gcc' tc_version='' tc_target='' expect_provider='' expect_release='' expect_krel='' expect_arch=''; while (($#)); do case "$1" in --toolchain-root) tcroot="$2"; shift 2;; --toolchain-cc) ccrel="$2"; shift 2;; --cross-prefix) prefix="$2"; shift 2;; --toolchain-tree-sha256) tc_tree="$2"; shift 2;; --toolchain-family) tc_family="$2"; shift 2;; --toolchain-version) tc_version="$2"; shift 2;; --toolchain-target) tc_target="$2"; shift 2;; --module) module="$2"; shift 2;; --jobs) jobs="$2"; shift 2;; --kernel-arch) karch_arg="$2"; shift 2;; --expect-provider) expect_provider="$2"; shift 2;; --expect-release) expect_release="$2"; shift 2;; --expect-kernel-release) expect_krel="$2"; shift 2;; --expect-target-arch) expect_arch="$2"; shift 2;; *) die "unknown run-module option: $1";; esac; done
  [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die "jobs must be a positive decimal integer: $jobs"
  verify_installed "$id"; local o m root build target_arch exec_arch cc_real ka tc_json be_tc_tree be_tc_family be_tc_version be_tc_target be_tc_cc expected_ka; o="$(objdir "$id")"; m="$o/manifest.json"; root="$o/root"; build="$(json_get "$m" '.build_dir_rel')"; target_arch="$(canonical_arch "$(json_get "$m" '.target_arch')")"; exec_arch="$(canonical_arch "$(json_get "$m" '.exec_arch')")"
  [[ -n "$expect_provider" && -n "$expect_release" && -n "$expect_krel" && -n "$expect_arch" ]] || die "run-module requires exact target identity (--expect-provider/--expect-release/--expect-kernel-release/--expect-target-arch)"
  [[ "$(json_get "$m" '.provider')" == "$expect_provider" ]] || die "buildenv provider does not match target: expected $expect_provider"
  [[ "$(json_get "$m" '.release')" == "$expect_release" ]] || die "buildenv release does not match target: expected $expect_release"
  [[ "$(json_get "$m" '.kernel_release')" == "$expect_krel" ]] || die "buildenv kernel release does not match target: expected $expect_krel"
  [[ "$target_arch" == "$(canonical_arch "$expect_arch")" ]] || die "buildenv target architecture does not match target: expected $(canonical_arch "$expect_arch"), got $target_arch"
  expected_ka="$(karch "$target_arch")"; [[ -z "$karch_arg" || "$karch_arg" == "$expected_ka" ]] || die "kernel ARCH mismatch: target $target_arch requires ARCH=$expected_ka, got $karch_arg"
  [[ "$exec_arch" == "$(host_arch)" ]] || die "buildenv execution architecture $exec_arch does not match host $(host_arch)"; [[ "$(json_get "$m" '.compiler_contract')" == gcc-v1 ]] || die "unsupported buildenv compiler contract"; [[ -d "$module" ]] || die "module directory missing"; tcroot="$(readlink -f "$tcroot")"; [[ -d "$tcroot" ]] || die "toolchain root missing"; [[ -x "$TOOLCHAIN_BOUNDARY_BIN" ]] || die "toolchain boundary helper missing: $TOOLCHAIN_BOUNDARY_BIN"; [[ -n "$tc_tree" ]] || die "hermetic build requires an externally bound toolchain tree digest"
  be_tc_tree="$(json_get "$m" '.toolchain_tree_sha256' 2>/dev/null || true)"; be_tc_family="$(json_get "$m" '.toolchain_family' 2>/dev/null || true)"; be_tc_version="$(json_get "$m" '.toolchain_version' 2>/dev/null || true)"; be_tc_target="$(json_get "$m" '.toolchain_target' 2>/dev/null || true)"; be_tc_cc="$(json_get "$m" '.toolchain_cc_relpath' 2>/dev/null || true)"
  [[ -n "$be_tc_tree" ]] || die "buildenv does not pin a toolchain tree; recreate it with current KLab"
  [[ "$tc_tree" == "$be_tc_tree" ]] || die "toolchain/buildenv binding mismatch: $tc_tree != $be_tc_tree"
  [[ -z "$be_tc_family" || "$tc_family" == "$be_tc_family" ]] || die "toolchain/buildenv compiler family mismatch"
  [[ -z "$be_tc_version" || "$tc_version" == "$be_tc_version" ]] || die "toolchain/buildenv compiler version mismatch"
  [[ -z "$be_tc_target" || "$be_tc_target" == unknown || "$tc_target" == "$be_tc_target" ]] || die "toolchain/buildenv compiler target mismatch"
  [[ -z "$be_tc_cc" || "$ccrel" == "$be_tc_cc" ]] || die "toolchain/buildenv compiler path mismatch"
  local tc_args=(verify --root "$tcroot" --cc "$ccrel" --tree-sha256 "$tc_tree" --family "$tc_family" --json); [[ -n "$tc_version" ]] && tc_args+=(--version "$tc_version"); [[ -n "$tc_target" ]] && tc_args+=(--target "$tc_target"); tc_json="$($TOOLCHAIN_BOUNDARY_BIN "${tc_args[@]}")"
  local p_cc p_cc1 p_as p_ld p_ar p_nm p_objcopy p_objdump p_strip p_readelf p_addr2line p_size p_strings p_ranlib tc_path
  IFS=$'\t' read -r p_cc p_cc1 p_as p_ld p_ar p_nm p_objcopy p_objdump p_strip p_readelf p_addr2line p_size p_strings p_ranlib < <(python3 - "$tc_json" <<'PY_TC_PROGRAMS'
import json,sys,posixpath
p=json.loads(sys.argv[1])['programs']
print('\t'.join(p[x] for x in ('cc','cc1','as','ld','ar','nm','objcopy','objdump','strip','readelf','addr2line','size','strings','ranlib')))
PY_TC_PROGRAMS
  )
  tc_path="$(python3 - "$tc_json" <<'PY_TC_PATH'
import json,sys,posixpath
p=json.loads(sys.argv[1])['programs']; dirs=[]
for rel in p.values():
 d=posixpath.dirname(rel) or '.'; q='/tmp/klab-toolchain/'+d
 if q not in dirs: dirs.append(q)
print(':'.join(dirs))
PY_TC_PATH
  )"
  cc_real="$(real_inside "$tcroot" "$p_cc")" || die "verified compiler escapes toolchain root"; [[ -x "$cc_real" ]] || die "verified compiler is not executable"; local bwrap_bin; bwrap_bin="$(command -v bwrap || true)"; [[ -n "$bwrap_bin" ]] || die "hermetic buildenv requires bwrap"; ka="${karch_arg:-$(karch "$target_arch")}";
  local tcbase=/tmp/klab-toolchain tc_cc tc_as tc_ld tc_ar tc_nm tc_objcopy tc_objdump tc_strip tc_readelf tc_addr2line tc_size tc_strings tc_ranlib tc_prefix=''
  tc_cc="$tcbase/$p_cc"; tc_as="$tcbase/$p_as"; tc_ld="$tcbase/$p_ld"; tc_ar="$tcbase/$p_ar"; tc_nm="$tcbase/$p_nm"; tc_objcopy="$tcbase/$p_objcopy"; tc_objdump="$tcbase/$p_objdump"; tc_strip="$tcbase/$p_strip"; tc_readelf="$tcbase/$p_readelf"; tc_addr2line="$tcbase/$p_addr2line"; tc_size="$tcbase/$p_size"; tc_strings="$tcbase/$p_strings"; tc_ranlib="$tcbase/$p_ranlib"; [[ -n "$prefix" ]] && tc_prefix="$tcbase/$prefix"
  # Host tools come only from the captured buildenv. Target compiler/binutils are
  # passed explicitly, and GCC's own helper directories precede buildenv /usr/bin.
  local sandbox_path="${tc_path:+$tc_path:}/usr/bin:/bin:/usr/sbin:/sbin"
  local make_args=(/usr/bin/make -C "/$build" M=/tmp/klab-work/module -j"$jobs" ARCH="$ka" CC="$tc_cc" AS="$tc_as" LD="$tc_ld" AR="$tc_ar" NM="$tc_nm" OBJCOPY="$tc_objcopy" OBJDUMP="$tc_objdump" STRIP="$tc_strip" READELF="$tc_readelf" ADDR2LINE="$tc_addr2line" SIZE="$tc_size" STRINGS="$tc_strings" RANLIB="$tc_ranlib" HOSTCC=/usr/bin/gcc)
  [[ -n "$tc_prefix" ]] && make_args+=(CROSS_COMPILE="$tc_prefix")
  make_args+=(modules)
  env -i HOME=/tmp USER=klab LOGNAME=klab LANG=C LC_ALL=C PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    "$bwrap_bin" --die-with-parent --unshare-all --ro-bind "$root" / --proc /proc --dev /dev --tmpfs /tmp --dir /tmp/klab-work --dir /tmp/klab-work/module --dir "$tcbase" \
      --ro-bind "$tcroot" "$tcbase" --bind "$(readlink -f "$module")" /tmp/klab-work/module --chdir /tmp/klab-work/module \
      /usr/bin/env -i HOME=/tmp USER=klab LOGNAME=klab LANG=C LC_ALL=C PATH="$sandbox_path" "${make_args[@]}"
}
run_module_native(){
  local id="$1"; shift
  local dtid='' module='' jobs="${KLAB_JOBS:-4}" karch_arg='' expect_provider='' expect_release='' expect_krel='' expect_arch=''
  while (($#)); do case "$1" in
    --distro-toolchain-id) dtid="$2"; shift 2;;
    --module) module="$2"; shift 2;;
    --jobs) jobs="$2"; shift 2;;
    --kernel-arch) karch_arg="$2"; shift 2;;
    --expect-provider) expect_provider="$2"; shift 2;;
    --expect-release) expect_release="$2"; shift 2;;
    --expect-kernel-release) expect_krel="$2"; shift 2;;
    --expect-target-arch) expect_arch="$2"; shift 2;;
    *) die "unknown run-module-native option: $1";;
  esac; done
  [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die "jobs must be a positive decimal integer: $jobs"
  [[ -n "$expect_provider" && -n "$expect_release" && -n "$expect_krel" && -n "$expect_arch" ]] || die "run-module-native requires exact target identity"
  [[ -d "$module" ]] || die "module directory missing"
  verify_installed "$id"
  local o m root build target_arch exec_arch ka dt_json cc as ld ccver cctarget asver ldver bwrap_bin pinned_dtid contract
  o="$(objdir "$id")"; m="$o/manifest.json"; root="$o/root"; build="$(json_get "$m" '.build_dir_rel')"
  target_arch="$(canonical_arch "$(json_get "$m" '.target_arch')")"; exec_arch="$(canonical_arch "$(json_get "$m" '.exec_arch')")"
  contract="$(json_get "$m" '.compiler_contract')"; [[ "$contract" == distro-native-v1 ]] || die "buildenv is not bound for distro-native execution"
  pinned_dtid="$(json_get "$m" '.distro_toolchain_id')"; [[ "$pinned_dtid" =~ ^[0-9a-f]{64}$ ]] || die "buildenv has no valid pinned distro-toolchain ID"
  [[ -z "$dtid" || "$dtid" == "$pinned_dtid" ]] || die "requested distro-toolchain does not match buildenv binding"
  dtid="$pinned_dtid"
  [[ "$(json_get "$m" '.provider')" == "$expect_provider" ]] || die "buildenv provider does not match target"
  [[ "$(json_get "$m" '.release')" == "$expect_release" ]] || die "buildenv release does not match target"
  [[ "$(json_get "$m" '.kernel_release')" == "$expect_krel" ]] || die "buildenv kernel release does not match target"
  [[ "$target_arch" == "$(canonical_arch "$expect_arch")" ]] || die "buildenv target architecture does not match target"
  native_exec_supported "$exec_arch" || die "buildenv execution architecture $exec_arch is not executable on host $(host_arch); enable a persistent binfmt handler"
  ka="${karch_arg:-$(karch "$target_arch")}"; [[ "$ka" == "$(karch "$target_arch")" ]] || die "kernel ARCH mismatch"
  [[ -x "$DISTRO_TOOLCHAIN_BIN" ]] || die "distro toolchain helper missing: $DISTRO_TOOLCHAIN_BIN"
  dt_json="$(KLAB_ROOT="$KLAB_ROOT" KLAB_HOME="$KLAB_ROOT" "$DISTRO_TOOLCHAIN_BIN" assert-installed "$dtid" --provider "$expect_provider" --release "$expect_release" --arch "$target_arch" --json)"
  IFS=$'\t' read -r cc as ld ccver cctarget asver ldver < <(python3 - "$dt_json" <<'PY_NATIVE_META'
import json,sys
c=json.loads(sys.argv[1])['compiler']
print('\t'.join(str(c[k]) for k in ('cc_path','as_path','ld_path','cc_version','cc_target','as_version','ld_version')))
PY_NATIVE_META
  )
  for p in "$cc" "$as" "$ld"; do image_exec_inside "$root" "$p" || die "distro-native tool is missing from captured buildenv root: $p"; done
  bwrap_bin="$(command -v bwrap || true)"; [[ -n "$bwrap_bin" ]] || die "hermetic distro-native build requires bwrap"
  env -i HOME=/tmp USER=klab LOGNAME=klab LANG=C LC_ALL=C PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    "$bwrap_bin" --die-with-parent --unshare-all --ro-bind "$root" / --proc /proc --dev /dev --tmpfs /tmp \
      --dir /tmp/klab-work --dir /tmp/klab-work/module --bind "$(readlink -f "$module")" /tmp/klab-work/module --chdir /tmp/klab-work/module \
      /bin/sh -eu -c '
        cc="$1"; as="$2"; ld="$3"; ccver="$4"; cctarget="$5"; asver="$6"; ldver="$7"; build="$8"; jobs="$9"; ka="${10}"
        gotcc=$($cc -dumpfullversion 2>/dev/null || true); case "$gotcc" in *.*.*) ;; *) gotcc=$($cc --version | head -n1 | grep -oE "[0-9]+(\.[0-9]+){2,3}" | head -n1 || true);; esac; [ -n "$gotcc" ] || gotcc=$($cc -dumpversion); gottr=$($cc -dumpmachine)
        case "$ccver" in "$gotcc"|"$gotcc".*) ;; *) echo "distro-native GCC mismatch: expected $ccver got $gotcc" >&2; exit 61;; esac
        [ "$gottr" = "$cctarget" ] || { echo "distro-native GCC target mismatch: expected $cctarget got $gottr" >&2; exit 62; }
        # Fedora Koji compiler metadata derives the binutils version from the
        # exact RPM recorded in the kernel buildroot.  Old Fedora snapshot RPMs
        # (notably F20 binutils 2.23.88.0.1) do not necessarily print the RPM
        # Version string verbatim in the GNU as/ld banner.  The exact RPM set is
        # already sealed by the distro-toolchain artifact, so for Fedora prove
        # that /usr/bin/as and /usr/bin/ld are owned by the expected binutils
        # package/version and merely require their version commands to execute.
        # Other providers record the executable-reported version and retain the
        # banner comparison.
        if [ "${11}" = fedora ]; then
          command -v rpm >/dev/null 2>&1 || { echo "distro-native Fedora root has no rpm database" >&2; exit 63; }
          as_owner=$(rpm -qf --qf "%{NAME}" "$as" 2>/dev/null || true)
          ld_owner=$(rpm -qf --qf "%{NAME}" "$ld" 2>/dev/null || true)
          binver=$(rpm -q --qf "%{VERSION}" binutils 2>/dev/null || true)
          [ "$as_owner" = binutils ] && [ "$ld_owner" = binutils ] || {
            echo "distro-native Fedora binutils ownership mismatch: as=$as_owner ld=$ld_owner" >&2; exit 63; }
          [ "$binver" = "$asver" ] && [ "$binver" = "$ldver" ] || {
            echo "distro-native Fedora binutils RPM mismatch: expected as=$asver ld=$ldver got=$binver" >&2; exit 63; }
          $as --version >/dev/null 2>&1 || { echo "distro-native Fedora assembler is not executable" >&2; exit 63; }
          $ld --version >/dev/null 2>&1 || { echo "distro-native Fedora linker is not executable" >&2; exit 64; }
        else
          as_banner=$($as --version | head -n1 || true)
          ld_banner=$($ld --version | head -n1 || true)
          printf "%s\n" "$as_banner" | grep -F "$asver" >/dev/null || { echo "distro-native assembler mismatch: expected $asver got: $as_banner" >&2; exit 63; }
          printf "%s\n" "$ld_banner" | grep -F "$ldver" >/dev/null || { echo "distro-native linker mismatch: expected $ldver got: $ld_banner" >&2; exit 64; }
        fi
        # The sandbox root is the captured distro image, but make/kbuild also
        # invokes ordinary host utilities.  Fail closed on the conservative
        # baseline instead of discovering a missing inherited provider tool
        # halfway through a build.  Perl/Python/pahole are intentionally not
        # universal requirements: individual kernel/config trees may add them.
        [ -s /var/lib/klab/host-tool-owners.tsv ] || { echo "distro-native host-tool ownership inventory missing" >&2; exit 65; }
        unalias -a 2>/dev/null || true
        for t in /bin/sh /usr/bin/make awk sed grep find xargs basename dirname tr cut sort head mkdir rm cp mv ln cat; do
          case "$t" in /*) [ -x "$t" ] || { echo "distro-native host-tool baseline missing: $t" >&2; exit 65; };;
            *) command -v "$t" >/dev/null 2>&1 || { echo "distro-native host-tool baseline missing: $t" >&2; exit 65; };; esac
        done
        # Keep inner quotes double-quoted: this command is embedded in an outer single-quoted shell script.
        while IFS="$(printf "\t")" read -r logical resolved owner; do
          [ -n "$logical" ] && [ -n "$resolved" ] && [ -n "$owner" ] || { echo "malformed host-tool ownership inventory" >&2; exit 66; }
          [ -x "$resolved" ] || { echo "recorded host-tool path missing: $resolved" >&2; exit 66; }
          # Re-prove the ownership assertion from the sealed distro package
          # database at execution time.  The TSV is content-addressed evidence,
          # but without this check a deliberately/accidentally false owner row
          # could still name any package that merely exists in the inventory.
          # Query the same resolved path used during capture so usrmerge and
          # alternatives do not silently change the semantic assertion.
          actual_owner=
          if command -v dpkg-query >/dev/null 2>&1; then
            actual_owner=$(dpkg-query -S "$resolved" 2>/dev/null | head -n1 | cut -d: -f1 || true)
            if [ -z "$actual_owner" ]; then
              case "$resolved" in
                /usr/bin/*|/usr/sbin/*|/usr/lib/*|/usr/lib64/*)
                  dpkg_path=${resolved#/usr}
                  actual_owner=$(dpkg-query -S "$dpkg_path" 2>/dev/null | head -n1 | cut -d: -f1 || true)
                  ;;
              esac
            fi
          elif command -v rpm >/dev/null 2>&1; then
            actual_owner=$(rpm -qf --qf "%{NAME}\n" "$resolved" 2>/dev/null | head -n1 || true)
          elif command -v apk >/dev/null 2>&1; then
            actual_owner=$(apk info -W "$resolved" 2>/dev/null | sed -n "s/.* is owned by //p" | sed "s/-[0-9][0-9.]*-r[0-9][0-9]*$//" | head -n1 || true)
          else
            echo "sealed root has no supported package ownership database (dpkg, rpm, or apk)" >&2; exit 67
          fi
          [ -n "$actual_owner" ] || { echo "cannot re-prove host-tool package owner: $resolved" >&2; exit 67; }
          [ "$actual_owner" = "$owner" ] || { echo "host-tool package owner mismatch: $resolved expected $owner got $actual_owner" >&2; exit 67; }
        done < /var/lib/klab/host-tool-owners.tsv
        /usr/bin/make -s -C "/$build" M=/tmp/klab-work/module clean >/dev/null 2>&1 || true
        exec /usr/bin/make -C "/$build" M=/tmp/klab-work/module -j"$jobs" ARCH="$ka" CC="$cc" HOSTCC="$cc" AS="$as" LD="$ld" modules
      ' sh "$cc" "$as" "$ld" "$ccver" "$cctarget" "$asver" "$ldver" "$build" "$jobs" "$ka" "$expect_provider"
}

cmd="${1:-}"; shift || true
case "$cmd" in
 create|verify|inspect|import|lookup|list|assert-installed) exec python3 "$PY" "$cmd" "$@";;
 verify-installed) (($#==1)) || die 'verify-installed requires ID'; verify_installed "$1"; echo "$1";;
 doctor) doctor;;
 run-module) (($#>=1)) || die 'run-module requires buildenv ID'; id="$1"; shift; run_module "$id" "$@";;
 run-module-native) (($#>=1)) || die 'run-module-native requires buildenv ID'; id="$1"; shift; run_module_native "$id" "$@";;
 help|-h|--help|'') usage;;
 *) usage; die "unknown command: $cmd";;
esac
