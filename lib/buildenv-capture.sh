#!/usr/bin/env bash
# Capture an exact provider module-build environment into a .klabbuildenv.
# This deliberately captures a complete sanitized provider root for format v1.

KLAB_BUILDENV_BIN="${KLAB_BUILDENV_BIN:-$SELF_DIR/klab-buildenv.sh}"
KLAB_BUILDENV_RECIPE_VERSION="${KLAB_BUILDENV_RECIPE_VERSION:-buildenv-v2-fullroot}"

if ! declare -F klab_arch_canonical >/dev/null 2>&1; then
  _klab_be_self="${SELF_DIR:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
  if [[ -f "$_klab_be_self/lib/arch-model.sh" ]]; then
    # shellcheck source=lib/arch-model.sh
    source "$_klab_be_self/lib/arch-model.sh"
  fi
  unset _klab_be_self
fi

klab_buildenv_runtime() {
  if [[ -n "${KLAB_CONTAINER_RUNTIME:-}" ]]; then command -v "$KLAB_CONTAINER_RUNTIME" >/dev/null || die "container runtime not found: $KLAB_CONTAINER_RUNTIME"; echo "$KLAB_CONTAINER_RUNTIME"
  elif command -v podman >/dev/null; then echo podman
  elif command -v docker >/dev/null; then echo docker
  else die "buildenv capture requires Docker or Podman on the staging host"; fi
}

klab_buildenv_owner_fix() {
  local p="$1" uid="$(id -u)" gid="$(id -g)"
  [[ -e "$p" ]] || return 0
  if [[ "$(id -u)" == 0 ]]; then chown -R "${SUDO_UID:-$uid}:${SUDO_GID:-$gid}" "$p" 2>/dev/null || true; else chown -R "$uid:$gid" "$p" 2>/dev/null || true; fi
}


klab_buildenv_canonical_arch() {
  if declare -F klab_arch_canonical >/dev/null 2>&1; then klab_arch_canonical "$1" 2>/dev/null || echo "$1"; return; fi
  echo "$1"
}

klab_buildenv_assert_staging_arch() {
  local host target mode="${3:-same-host-v1}"
  host="$(klab_buildenv_canonical_arch "$1")"
  target="$(klab_buildenv_canonical_arch "$2")"
  [[ "$host" == "$target" || "$mode" == provider-native-v1 ]] || \
    die "buildenv format v1 requires same-architecture staging or a provider-native container: host=$host target=$target"
}

klab_buildenv_verify_package_manifest() {
  local packages="$1" manifest="$2"
  python3 - "$packages" "$manifest" <<'PY_MANIFEST'
import hashlib,pathlib,re,sys
root=pathlib.Path(sys.argv[1]).resolve(); mf=pathlib.Path(sys.argv[2]).resolve()
if not mf.is_file(): raise SystemExit('package checksum manifest missing')
files=sorted([p for p in root.iterdir() if p.is_file() and p.suffix in ('.deb','.rpm','.apk')], key=lambda p:p.name)
rows={}
for raw in mf.read_text().splitlines():
    if not raw.strip(): continue
    m=re.fullmatch(r'([0-9a-fA-F]{64})\s+[ *]?(.+)', raw.strip())
    if not m: raise SystemExit(f'malformed package checksum row: {raw!r}')
    sha,name=m.group(1).lower(),m.group(2)
    if '/' in name or name in ('.','..'): raise SystemExit(f'unsafe package manifest path: {name}')
    if name in rows: raise SystemExit(f'duplicate package manifest entry: {name}')
    rows[name]=sha
actual={p.name for p in files}
if set(rows)!=actual:
    raise SystemExit(f'package manifest set mismatch: manifest={sorted(rows)} actual={sorted(actual)}')
for p in files:
    h=hashlib.sha256(p.read_bytes()).hexdigest()
    if h!=rows[p.name]: raise SystemExit(f'package checksum mismatch: {p.name}')
PY_MANIFEST
}

klab_buildenv_require_image_id() {
  local rt="$1" image="$2" id
  id="$("$rt" image inspect --format '{{.Id}}' "$image" 2>/dev/null || true)"
  [[ "$id" =~ ^sha256:[0-9a-fA-F]{64}$ ]] || die "provider image does not resolve to a canonical content ID: $image (${id:-missing})"
  printf '%s\n' "${id,,}"
}

klab_buildenv_capture_container() {
  local provider="$1" release="$2" krel="$3" target_arch="$4" image="$5" setup="$6" packages="$7" install_script="$8" build_dir="$9" output="${10}"
  local rt name tmp root smoke exec_arch package_manifest image_id validate_package_manifest target_karch host_arch container_arch installed_inventory
  local compiler_contract distro_tc_id distro_tc_file distro_tc_root distro_tc_bin tcroot tcjson tc_cc tc_cc1 tc_as tc_ld tc_ar tc_nm tc_objcopy tc_objdump tc_strip tc_readelf tc_addr2line tc_size tc_strings tc_ranlib tc_path tc_prefix native_cc make_cc_arg aux_repo_dir dependency_archives dependency_provenance dependency_capture_command dependency_repository_url dependency_metadata_file dependency_capture_stage
  rt="$(klab_buildenv_runtime)"; tmp="$(mktemp -d)"; root="$tmp/root"; smoke="$tmp/smoke"; mkdir -p "$root" "$smoke"
  host_arch="$(klab_buildenv_canonical_arch "$(uname -m)")"
  klab_buildenv_assert_staging_arch "$host_arch" "$target_arch" "${KLAB_BUILDENV_STAGING_MODE:-same-host-v1}"
  validate_package_manifest="${packages}/PACKAGES.sha256"
  [[ -f "$validate_package_manifest" ]] || die "provider package set is missing PACKAGES.sha256"
  klab_buildenv_verify_package_manifest "$packages" "$validate_package_manifest" || die "provider package manifest verification failed"
  image_id="$(klab_buildenv_require_image_id "$rt" "$image")"
  compiler_contract="${KLAB_BUILDENV_COMPILER_CONTRACT:-gcc-v1}"; distro_tc_id="${KLAB_BUILDENV_DISTRO_TOOLCHAIN_ID:-}"; distro_tc_file="${KLAB_BUILDENV_DISTRO_TOOLCHAIN_FILE:-}"
  tcroot="${KLAB_BUILDENV_TOOLCHAIN_ROOT:-}"; tcjson="${KLAB_BUILDENV_TOOLCHAIN_JSON:-}"
  native_cc="${KLAB_BUILDENV_NATIVE_CC:-}"; make_cc_arg=""; aux_repo_dir="${KLAB_BUILDENV_AUX_REPO_DIR:-}"
  dependency_archives="${KLAB_BUILDENV_DEPENDENCY_ARCHIVES:-}"; dependency_provenance="${KLAB_BUILDENV_DEPENDENCY_PROVENANCE:-}"
  dependency_capture_command="${KLAB_BUILDENV_DEPENDENCY_CAPTURE_COMMAND:-}"; dependency_repository_url="${KLAB_BUILDENV_DEPENDENCY_REPOSITORY_URL:-}"
  dependency_metadata_file="${KLAB_BUILDENV_DEPENDENCY_METADATA_FILE:-}"
  dependency_capture_stage="$tmp/dependency-capture"
  [[ -z "$dependency_capture_command" || -n "$dependency_repository_url" ]] || die "automatic dependency capture requires a repository provenance URL"
  [[ -z "$dependency_capture_command" || -z "$dependency_archives" ]] || die "automatic and presealed dependency closures are mutually exclusive"
  [[ -z "$dependency_archives" && -z "$dependency_provenance" || -n "$dependency_archives" && -n "$dependency_provenance" ]] || die "dependency archives and provenance must be supplied together"
  if [[ -n "$dependency_archives" ]]; then
    [[ -d "$dependency_archives" && -f "$dependency_archives/PACKAGES.sha256" ]] || die "dependency archive closure is missing or has no PACKAGES.sha256"
    [[ -f "$dependency_provenance" ]] || die "dependency provenance file is missing"
    dependency_archives="$(readlink -f "$dependency_archives")"; dependency_provenance="$(readlink -f "$dependency_provenance")"
  fi
  if [[ -n "$native_cc" ]]; then
    [[ "$native_cc" =~ ^/?[A-Za-z0-9._+/-]+$ ]] || die "invalid buildenv native compiler path: $native_cc"
    [[ "$native_cc" == /* ]] || native_cc="/usr/bin/$native_cc"
    make_cc_arg="CC=$native_cc"
  fi
  case "$compiler_contract" in
    gcc-v1) ;;
    distro-native-v1)
      [[ "$distro_tc_id" =~ ^[0-9a-f]{64}$ ]] || die "distro-native buildenv capture requires KLAB_BUILDENV_DISTRO_TOOLCHAIN_ID"
      [[ -f "$distro_tc_file" ]] || die "distro-native buildenv capture requires KLAB_BUILDENV_DISTRO_TOOLCHAIN_FILE"
      distro_tc_bin="${KLAB_DISTRO_TOOLCHAIN_BIN:-$SELF_DIR/klab-distro-toolchain.sh}"
      [[ -x "$distro_tc_bin" ]] || die "distro-toolchain helper is missing: $distro_tc_bin"
      "$distro_tc_bin" verify "$distro_tc_file" >/dev/null
      distro_tc_root="$tmp/distro-toolchain"; mkdir -p "$distro_tc_root"
      tar --zstd -xf "$distro_tc_file" -C "$distro_tc_root" --no-same-owner
      [[ -d "$distro_tc_root/packages" ]] || die "distro-toolchain artifact contains no package directory"
      tcroot=; tcjson=
      ;;
    *) die "unsupported buildenv compiler contract: $compiler_contract";;
  esac
  target_karch="$(klab_arch_kernel_arch "$target_arch" 2>/dev/null || true)"
  [[ -n "$target_karch" ]] || die "unsupported target architecture for buildenv capture: $target_arch"
  name="klab-buildenv-${provider}-$$-${RANDOM:-0}"
  trap '"$rt" rm -f "$name" >/dev/null 2>&1 || true; chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' RETURN
  cat >"$smoke/Makefile" <<'EOF'
obj-m += klab_buildenv_smoke.o
EOF
  cat >"$smoke/klab_buildenv_smoke.c" <<'EOF'
#include <linux/module.h>
static int __init klab_be_init(void){return 0;}
static void __exit klab_be_exit(void){}
module_init(klab_be_init); module_exit(klab_be_exit); MODULE_LICENSE("GPL");
EOF
  local create_args=(create --name "$name" -v "$packages:/pkgs:ro" -v "$smoke:/klab-smoke")
  if [[ -n "$dependency_capture_command" ]]; then
    mkdir -p "$dependency_capture_stage/packages"
    create_args+=(-v "$dependency_capture_stage:/klab-dependency-capture")
    if [[ -n "$dependency_metadata_file" ]]; then
      [[ -f "$dependency_metadata_file" ]] || die "dependency repository metadata file not found: $dependency_metadata_file"
      dependency_metadata_file="$(readlink -f "$dependency_metadata_file")"
      create_args+=(-v "$dependency_metadata_file:/klab-dependency-metadata:ro")
    fi
  fi
  [[ -z "${distro_tc_root:-}" ]] || create_args+=(-v "$distro_tc_root/packages:/klab-distro-toolchain-packages:ro")
  if [[ -n "$aux_repo_dir" ]]; then
    [[ -d "$aux_repo_dir" ]] || die "buildenv auxiliary repository directory not found: $aux_repo_dir"
    aux_repo_dir="$(readlink -f "$aux_repo_dir")"
    create_args+=(-v "$aux_repo_dir:/klab-buildenv-aux-repo:ro")
  fi
  if declare -F klab_provider_prepare_mirror_args >/dev/null 2>&1; then
    klab_provider_prepare_mirror_args "$provider"
    create_args+=("${KLAB_PROVIDER_MIRROR_ARGS[@]}")
  fi
  if [[ -n "$tcroot" || -n "$tcjson" ]]; then
    [[ -n "$tcroot" && -d "$tcroot" && -n "$tcjson" ]] || die "buildenv/toolchain pair validation requires both KLAB_BUILDENV_TOOLCHAIN_ROOT and KLAB_BUILDENV_TOOLCHAIN_JSON"
    create_args+=(-v "$tcroot:/klab-toolchain:ro")
  fi
  "$rt" "${create_args[@]}" "$image" /bin/sh -c 'trap : TERM INT; while :; do sleep 3600; done' >/dev/null
  "$rt" start "$name" >/dev/null
  container_arch="$(klab_buildenv_canonical_arch "$("$rt" exec "$name" uname -m | tr -d '\r')")"
  [[ "$container_arch" == "$(klab_buildenv_canonical_arch "$target_arch")" ]] || die "provider container execution architecture mismatch: container=$container_arch target=$(klab_buildenv_canonical_arch "$target_arch")"

  # First prove that the provider's own build environment is complete. This
  # distinguishes a broken provider/header closure from a bound-toolchain issue.
  "$rt" exec "$name" /bin/sh -lc "set -e
$setup
$install_script
[ -d '$build_dir' ] || { echo 'expected build tree missing: $build_dir' >&2; exit 41; }
[ -f '$build_dir/Makefile' ] && [ -f '$build_dir/scripts/Makefile.build' ] || { echo 'incomplete build tree' >&2; exit 41; }
# A distro ABI release need not equal the upstream base reported by the
# top-level Makefile. Validate the artifact KLab actually consumes.
set +e
make -s -C '$build_dir' M=/klab-smoke ${make_cc_arg:+$make_cc_arg} modules
rc=\$?
set -e
[ \$rc -eq 0 ] || { echo buildenv-smoke-module-compilation-failed-rc=\$rc >&2; exit \$rc; }
ko=\$(find /klab-smoke -name '*.ko' -print -quit)
[ -n \"\$ko\" ] || { echo 'buildenv smoke module was not produced' >&2; exit 43; }
vm=\$(modinfo -F vermagic \"\$ko\" 2>/dev/null || true)
if [ -z \"\$vm\" ] && command -v strings >/dev/null 2>&1; then
  vm=\$(strings \"\$ko\" | sed -n 's/^vermagic=//p' | head -n1 || true)
fi
case \"\$vm\" in
  '$krel '*) ;;
  *) echo \"module vermagic mismatch: \${vm:-missing} != $krel\" >&2; exit 42 ;;
esac"

  # For distro-native mode the first smoke build is the exact compiler/binutils
  # execution path that will be preserved in the captured root. Gate the actual
  # emitted relocations before packaging; vermagic alone is not sufficient for
  # vintage kernels.
  if [[ "$compiler_contract" == distro-native-v1 ]]; then
    local native_ko native_as_ver native_vrc=0 vintage_bin="${KLAB_VINTAGE_VALIDATE_BIN:-$SELF_DIR/klab-vintage-validate.sh}"
    native_ko="$(find "$smoke" -name '*.ko' -print -quit)"
    native_as_ver="$("$rt" exec "$name" as --version 2>/dev/null | head -n1 || true)"
    [[ -n "$native_ko" ]] || die "distro-native smoke module disappeared before vintage validation"
    "$vintage_bin" --module "$native_ko" --arch "$target_arch" --kernel-release "$krel" --binutils-version "$native_as_ver" --strict-vintage >&2 || native_vrc=$?
    case "$native_vrc" in
      0) ;;
      2) [[ "${KLAB_ALLOW_UNPROVEN_VINTAGE_RELOCS:-0}" == 1 ]] || die "distribution-native toolchain emits relocation semantics not proven compatible with vintage target $provider:$release:$krel" ;;
      *) die "distribution-native toolchain emits relocations rejected by vintage compatibility validation for $provider:$release:$krel" ;;
    esac
  fi

  # Then prove the exact sealed toolchain + provider build root pair. A provider
  # image compiling with its native GCC is insufficient: the air-gapped worker
  # will use the separately transferred .klabtoolchain, and its compiler/helper
  # ABI must be compatible with this captured root.
  if [[ -n "$tcroot" ]]; then
    IFS=$'\t' read -r tc_cc tc_cc1 tc_as tc_ld tc_ar tc_nm tc_objcopy tc_objdump tc_strip tc_readelf tc_addr2line tc_size tc_strings tc_ranlib tc_path < <(python3 - "$tcjson" <<'PY_TC_PAIR'
import json,sys,posixpath
m=json.loads(sys.argv[1]); p=m['programs']
names=('cc','cc1','as','ld','ar','nm','objcopy','objdump','strip','readelf','addr2line','size','strings','ranlib')
vals=[p[n] for n in names]
dirs=[]
for rel in p.values():
    d=posixpath.dirname(rel) or '.'
    q='/klab-toolchain/'+d
    if q not in dirs: dirs.append(q)
print('\t'.join(vals+[':'.join(dirs)]))
PY_TC_PAIR
    )
    tc_prefix=''
    if [[ "$(basename "$tc_cc")" == *-gcc ]]; then tc_prefix="/klab-toolchain/${tc_cc%gcc}"; fi
    local pair_env=(
      -e "KLAB_BUILD_DIR=$build_dir" -e "KLAB_KERNEL_RELEASE=$krel" -e "KLAB_KERNEL_ARCH=$target_karch"
      -e "KLAB_TC_PATH=$tc_path" -e "KLAB_TC_CC=/klab-toolchain/$tc_cc" -e "KLAB_TC_AS=/klab-toolchain/$tc_as"
      -e "KLAB_TC_LD=/klab-toolchain/$tc_ld" -e "KLAB_TC_AR=/klab-toolchain/$tc_ar" -e "KLAB_TC_NM=/klab-toolchain/$tc_nm"
      -e "KLAB_TC_OBJCOPY=/klab-toolchain/$tc_objcopy" -e "KLAB_TC_OBJDUMP=/klab-toolchain/$tc_objdump" -e "KLAB_TC_STRIP=/klab-toolchain/$tc_strip"
      -e "KLAB_TC_READELF=/klab-toolchain/$tc_readelf" -e "KLAB_TC_ADDR2LINE=/klab-toolchain/$tc_addr2line" -e "KLAB_TC_SIZE=/klab-toolchain/$tc_size"
      -e "KLAB_TC_STRINGS=/klab-toolchain/$tc_strings" -e "KLAB_TC_RANLIB=/klab-toolchain/$tc_ranlib" -e "KLAB_TC_PREFIX=$tc_prefix"
    )
    "$rt" exec "${pair_env[@]}" "$name" /bin/sh -lc '
set -eu
make -s -C "$KLAB_BUILD_DIR" M=/klab-smoke clean >/dev/null 2>&1 || true
PATH="$KLAB_TC_PATH:/usr/bin:/bin:/usr/sbin:/sbin" \
  make -C "$KLAB_BUILD_DIR" M=/klab-smoke ARCH="$KLAB_KERNEL_ARCH" \
    CC="$KLAB_TC_CC" AS="$KLAB_TC_AS" LD="$KLAB_TC_LD" AR="$KLAB_TC_AR" NM="$KLAB_TC_NM" \
    OBJCOPY="$KLAB_TC_OBJCOPY" OBJDUMP="$KLAB_TC_OBJDUMP" STRIP="$KLAB_TC_STRIP" READELF="$KLAB_TC_READELF" \
    ADDR2LINE="$KLAB_TC_ADDR2LINE" SIZE="$KLAB_TC_SIZE" STRINGS="$KLAB_TC_STRINGS" RANLIB="$KLAB_TC_RANLIB" \
    HOSTCC=/usr/bin/gcc ${KLAB_TC_PREFIX:+CROSS_COMPILE="$KLAB_TC_PREFIX"} modules
ko=$(find /klab-smoke -name "*.ko" -print -quit)
[ -n "$ko" ] || { echo "bound-toolchain pair smoke module was not produced" >&2; exit 44; }
vm=$(modinfo -F vermagic "$ko" 2>/dev/null || true)
if [ -z "$vm" ]; then
  vm=$($KLAB_TC_STRINGS "$ko" | sed -n 's/^vermagic=//p' | head -n1 || true)
fi
case "$vm" in
  "$KLAB_KERNEL_RELEASE "*) ;;
  *) echo "bound-toolchain module vermagic mismatch: ${vm:-missing} != $KLAB_KERNEL_RELEASE" >&2; exit 45 ;;
esac
' || die "captured build environment is not compatible with the exact sealed toolchain for $provider:$release:$krel"

    # Historical kernels can accept the right vermagic yet reject ELF
    # relocations introduced by a newer assembler. Run a conservative static
    # preflight on the exact module produced by the sealed pair. Source-backed
    # validation is authoritative when source is available elsewhere; distro
    # header-only targets use the vintage hazard rules and require explicit
    # opt-in if compatibility cannot be proven.
    local vintage_bin="${KLAB_VINTAGE_VALIDATE_BIN:-$SELF_DIR/klab-vintage-validate.sh}" pair_ko pair_as_ver pair_vrc=0
    pair_ko="$(find "$smoke" -type f -name '*.ko' -print -quit)"
    if [[ -x "$vintage_bin" && -n "$pair_ko" ]]; then
      pair_as_ver="$("$tcroot/$tc_as" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1 || true)"
      set +e
      "$vintage_bin" --module "$pair_ko" --arch "$target_arch" --kernel-release "$krel" --binutils-version "$pair_as_ver" --strict-vintage >&2
      pair_vrc=$?
      set -e
      if (( pair_vrc == 2 )); then
        if [[ "${KLAB_ALLOW_UNPROVEN_VINTAGE_RELOCS:-0}" == 1 ]]; then
          echo "klab-buildenv: WARNING: accepting unproven vintage relocation compatibility by explicit override" >&2
        else
          die "sealed toolchain emits relocation semantics not proven compatible with vintage target $provider:$release:$krel; use the distro-native toolchain or provide exact source/runtime proof (KLAB_ALLOW_UNPROVEN_VINTAGE_RELOCS=1 only for deliberate override)"
        fi
      elif (( pair_vrc != 0 )); then
        die "sealed toolchain emits relocations rejected by source-backed vintage compatibility validation for $provider:$release:$krel"
      fi
    fi
  fi

  # Seal a normalized inventory of the packages actually installed in the
  # provider build root. This is distinct from PACKAGES.sha256: the latter seals
  # downloaded archives; this records the dependency closure realized by the
  # package manager inside the build environment.
  # Record package ownership for the conservative host-tool baseline used by
  # distro-native kbuild.  This does not pretend observed tools are the whole
  # reconstruction closure; it makes the baseline auditable and prevents a
  # captured root from silently depending on an unowned provider-image file.
  "$rt" exec "$name" /bin/sh -lc '
set -eu
mkdir -p /var/lib/klab
: > /var/lib/klab/host-tool-owners.tsv
unalias -a 2>/dev/null || true
for t in /bin/sh /usr/bin/make awk sed grep find xargs basename dirname tr cut sort head mkdir rm cp mv ln cat; do
  case "$t" in /*) p="$t";; *) p=$(command -v "$t" || true);; esac
  [ -n "$p" ] && [ -x "$p" ] || { echo "missing kbuild baseline tool: $t" >&2; exit 66; }
  # Debian alternatives (notably /usr/bin/awk) are package-manager-managed
  # symlinks whose link pathname itself is not necessarily owned by a package.
  # Bind ownership to the final executable target instead.  This also makes the
  # recorded path agree with the object whose bytes are actually executed.
  resolved=$(readlink -f "$p" 2>/dev/null || true)
  [ -n "$resolved" ] && [ -x "$resolved" ] || { echo "cannot resolve kbuild baseline tool: $p" >&2; exit 66; }
  if command -v dpkg-query >/dev/null 2>&1; then
    owner=$(dpkg-query -S "$resolved" 2>/dev/null | head -n1 | cut -d: -f1 || true)
    # On usrmerged Debian systems readlink resolves /bin/* to /usr/bin/*,
    # while dpkg may retain the historical /bin/* pathname in its database.
    if [ -z "$owner" ]; then
      case "$resolved" in
        /usr/bin/*|/usr/sbin/*|/usr/lib/*|/usr/lib64/*)
          dpkg_path=${resolved#/usr}
          owner=$(dpkg-query -S "$dpkg_path" 2>/dev/null | head -n1 | cut -d: -f1 || true)
          ;;
      esac
    fi
  elif command -v rpm >/dev/null 2>&1; then
    owner=$(rpm -qf --qf "%{NAME}\n" "$resolved" 2>/dev/null | head -n1 || true)
  elif command -v apk >/dev/null 2>&1; then
    owner=$(apk info -W "$resolved" 2>/dev/null | sed -n "s/.* is owned by //p" | sed "s/-[0-9][0-9.]*-r[0-9][0-9]*$//" | head -n1 || true)
  else owner=; fi
  [ -n "$owner" ] || { echo "no owning package for kbuild baseline tool: $resolved (from $p)" >&2; exit 67; }
  printf "%s\t%s\t%s\n" "$t" "$resolved" "$owner" >> /var/lib/klab/host-tool-owners.tsv
done
LC_ALL=C sort -u -o /var/lib/klab/host-tool-owners.tsv /var/lib/klab/host-tool-owners.tsv
'

  installed_inventory="$tmp/installed-packages.tsv"
  case "$provider" in
    ubuntu|debian)
      "$rt" exec "$name" /bin/sh -lc "dpkg-query -W -f='\${Package}\t\${Version}\t\${Architecture}\n' | LC_ALL=C sort -u" >"$installed_inventory" ;;
    alpine)
      "$rt" exec "$name" /bin/sh -lc "apk info -v | sed -E 's/^(.+)-([0-9][^-]*-r[0-9]+)$/\1\t\2\tx86_64/' | LC_ALL=C sort -u" >"$installed_inventory" ;;
    centos|fedora|rhel|rocky|almalinux)
      "$rt" exec "$name" /bin/sh -lc "rpm -qa --qf '%{NAME}\\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\\t%{ARCH}\\n' | grep -v '^gpg-pubkey[[:space:]]' | LC_ALL=C sort -u" >"$installed_inventory" ;;
    *) die "no installed-package inventory implementation for provider: $provider" ;;
  esac
  [[ -s "$installed_inventory" ]] || die "installed package inventory is empty for $provider:$release:$krel"

  if [[ -n "$dependency_capture_command" ]]; then
    "$rt" exec "$name" /bin/sh -lc "$dependency_capture_command"
    klab_buildenv_owner_fix "$dependency_capture_stage"
    [[ -d "$dependency_capture_stage/packages" && -f "$dependency_capture_stage/repository-state.tar" ]] || \
      die "provider dependency capture did not produce packages and repository metadata"
    dependency_archives="$tmp/dependency-closure"
    dependency_provenance="$tmp/dependency-provenance.json"
    local dependency_identity_args=()
    [[ ! -f "$dependency_capture_stage/archive-identities.tsv" ]] || dependency_identity_args=(--archive-identities "$dependency_capture_stage/archive-identities.tsv")
    "${KLAB_DEPENDENCY_SEAL_BIN:-$SELF_DIR/tools/seal-dependency-closure.py}" \
      --packages "$dependency_capture_stage/packages" --installed-inventory "$installed_inventory" \
      "${dependency_identity_args[@]}" --provider "$provider" --release "$release" \
      --repository "$dependency_repository_url" "$dependency_capture_stage/repository-state.tar" \
      --output "$dependency_archives" --provenance-output "$dependency_provenance" >/dev/null
  fi

  # Remove network/package-manager state before capture. The resulting root is a
  # build runtime, not a general-purpose container image.
  "$rt" exec "$name" /bin/sh -lc 'rm -rf /var/cache/apt/* /var/lib/apt/lists/* /var/cache/dnf/* /var/cache/yum/* /var/tmp/* /tmp/* 2>/dev/null || true'
  exec_arch="$container_arch"

  # Container exports may contain live pseudo-filesystems/runtime sockets. They
  # are neither reproducible nor required by kbuild, so exclude/delete them and
  # recreate empty mount points. --no-same-owner also prevents provider-root
  # ownership from poisoning a non-root KLab warehouse.
  "$rt" export "$name" | tar --no-same-owner \
    --exclude='./dev/*' --exclude='dev/*' \
    --exclude='./proc/*' --exclude='proc/*' \
    --exclude='./sys/*' --exclude='sys/*' \
    --exclude='./run/*' --exclude='run/*' \
    -C "$root" -xf -
  mkdir -p "$root/dev" "$root/proc" "$root/sys" "$root/run" "$root/tmp" "$root/var/tmp"
  find "$root" -xdev \( -type s -o -type p -o -type b -o -type c \) -delete 2>/dev/null || true
  # The content-addressed artifact is created and verified without privilege.
  # Preserve write/execute modes while making the extracted owner able to hash
  # every regular file and traverse every directory. Runtime mounts it read-only.
  chmod -R u+rX "$root"

  package_manifest="$validate_package_manifest"
  local -a buildenv_create_args=(create --root "$root" --provider "$provider" --release "$release" --kernel-release "$krel"
    --target-arch "$target_arch" --exec-arch "$exec_arch" --provider-image "$image_id" --recipe-version "$KLAB_BUILDENV_RECIPE_VERSION"
    --build-dir "${build_dir#/}" --package-manifest "$package_manifest" --installed-inventory "$installed_inventory"
    --compiler-contract "$compiler_contract" --distro-toolchain-id "$distro_tc_id"
    --toolchain-tree-sha256 "${KLAB_BUILDENV_TOOLCHAIN_TREE_SHA256:-}" --toolchain-family "${KLAB_BUILDENV_TOOLCHAIN_FAMILY:-}"
    --toolchain-version "${KLAB_BUILDENV_TOOLCHAIN_VERSION:-}" --toolchain-target "${KLAB_BUILDENV_TOOLCHAIN_TARGET:-}"
    --toolchain-cc-relpath "${KLAB_BUILDENV_TOOLCHAIN_CC_REL:-}" -o "$output")
  if [[ -n "$dependency_archives" ]]; then
    buildenv_create_args+=(--dependency-archives "$dependency_archives" --dependency-provenance "$dependency_provenance")
  fi
  "$KLAB_BUILDENV_BIN" "${buildenv_create_args[@]}"
  klab_buildenv_owner_fix "$output"

  # Final acceptance uses the exact offline execution path: import the newly
  # created artifact into a throwaway warehouse, mount its root read-only via
  # bwrap, bind the exact sealed toolchain, and compile the smoke module again.
  # This catches build trees that only work while writable in the provider
  # container (for example because kbuild tries to generate missing files).
  if [[ "$compiler_contract" == distro-native-v1 ]]; then
    command -v bwrap >/dev/null 2>&1 || die "buildenv capture requires bwrap for final distro-native read-only smoke validation"
    local post_home="$tmp/post-home" post_id
    post_id="$("$KLAB_BUILDENV_BIN" verify "$output" --deep)"
    KLAB_ROOT="$post_home" KLAB_HOME="$post_home" "$KLAB_BUILDENV_BIN" import "$output" >/dev/null
    KLAB_ROOT="$post_home" KLAB_HOME="$post_home" "${KLAB_DISTRO_TOOLCHAIN_BIN:-$SELF_DIR/klab-distro-toolchain.sh}" import "$distro_tc_file" >/dev/null
    find "$smoke" -mindepth 1 ! -name Makefile ! -name klab_buildenv_smoke.c -delete 2>/dev/null || true
    KLAB_ROOT="$post_home" KLAB_HOME="$post_home" "$KLAB_BUILDENV_BIN" run-module-native "$post_id" --module "$smoke" --jobs 1 --kernel-arch "$target_karch" \
      --expect-provider "$provider" --expect-release "$release" --expect-kernel-release "$krel" --expect-target-arch "$target_arch" >/dev/null || \
      die "captured .klabbuildenv failed final distro-native read-only artifact smoke validation for $provider:$release:$krel"
  elif [[ -n "$tcroot" ]]; then
    command -v bwrap >/dev/null 2>&1 || die "buildenv capture requires bwrap for final read-only artifact smoke validation"
    local post_home="$tmp/post-home" post_id post_prefix=''
    post_id="$("$KLAB_BUILDENV_BIN" verify "$output" --deep)"
    KLAB_ROOT="$post_home" KLAB_HOME="$post_home" "$KLAB_BUILDENV_BIN" import "$output" >/dev/null
    find "$smoke" -mindepth 1 ! -name Makefile ! -name klab_buildenv_smoke.c -delete 2>/dev/null || true
    if [[ "$(basename "${KLAB_BUILDENV_TOOLCHAIN_CC_REL:-}")" == *-gcc ]]; then
      post_prefix="${KLAB_BUILDENV_TOOLCHAIN_CC_REL%gcc}"
    fi
    local post_args=(run-module "$post_id" --toolchain-root "$tcroot" --toolchain-cc "${KLAB_BUILDENV_TOOLCHAIN_CC_REL}" \
      --toolchain-tree-sha256 "${KLAB_BUILDENV_TOOLCHAIN_TREE_SHA256}" --toolchain-family "${KLAB_BUILDENV_TOOLCHAIN_FAMILY:-gcc}" \
      --toolchain-version "${KLAB_BUILDENV_TOOLCHAIN_VERSION:-}" --toolchain-target "${KLAB_BUILDENV_TOOLCHAIN_TARGET:-}" \
      --module "$smoke" --jobs 1 --kernel-arch "$target_karch" --expect-provider "$provider" --expect-release "$release" \
      --expect-kernel-release "$krel" --expect-target-arch "$target_arch")
    [[ -n "$post_prefix" ]] && post_args+=(--cross-prefix "$post_prefix")
    KLAB_ROOT="$post_home" KLAB_HOME="$post_home" "$KLAB_BUILDENV_BIN" "${post_args[@]}" >/dev/null || \
      die "captured .klabbuildenv failed final read-only artifact smoke validation for $provider:$release:$krel"
  fi
  "$rt" rm -f "$name" >/dev/null 2>&1 || true
  chmod -R u+w "$tmp" 2>/dev/null || true
  rm -rf "$tmp"; trap - RETURN
}
