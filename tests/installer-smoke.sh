#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/src"
cat >"$T/src/kernel-lab.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LAB_HOME=/tmp/lab
BUNDLE_BIN="$SELF_DIR/klab-bundle.sh"
OFFLINE=0
SRC=/tmp/linux
ARCH=x86_64
JOBS=1
providers_show() { echo old; }
provider_list_apt() { :; }
cmd_provider_list() {
  [[ "$OFFLINE" != 1 ]] || die "offline mode: provider listing requires network access"
  local spec="$1" pattern="${2:-}"
  parse_target "$spec"
  case "$PROVIDER" in
    ubuntu|debian) provider_list_apt "$PROVIDER" "$DISTRO_RELEASE" "$pattern" ;;
    fedora) provider_list_fedora "$DISTRO_RELEASE" "$pattern" ;;
    centos) provider_list_centos "$DISTRO_RELEASE" "$pattern" ;;
    rhel) provider_list_rhel "$DISTRO_RELEASE" "$pattern" ;;
    freebsd) provider_list_freebsd "$DISTRO_RELEASE" ;;
    upstream) : ;;
    *) die "unknown provider '$PROVIDER'" ;;
  esac
}
extract_debs() { :; }
cmd_fetch() {
  local target="$1" bundle=/tmp/b
  parse_target "$target"
  case "$PROVIDER" in upstream|freebsd) return ;; esac
  case "$PROVIDER" in
    ubuntu|debian) fetch_apt_bundle "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$bundle" ;;
    fedora) fetch_fedora_bundle "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$bundle" ;;
    centos) fetch_centos_bundle "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$bundle" ;;
    rhel) fetch_rhel_bundle "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$bundle" ;;
    *) die "unknown provider '$PROVIDER'" ;;
  esac
}
cmd_info() { :; }
cmd_prepare() {
  local target="$1" provider="${1%%:*}" profile=normal output=/tmp/o.klab artifact_dir=/tmp/a tc_mode=none tc_dir=''
  if [[ "$provider" == upstream ]]; then :; else
    say "Fetching exact distro kernel artifacts for $target"
    cmd_fetch "$target" >/dev/null
  fi
  local args=(create "$target" --profile "$profile" -o "$output")
  bundle_tool "${args[@]}"
}
cmd_import_bundle() {
  (($# >= 1)) || die "usage"
  bundle_tool import "$@"
}
build_external_module_bundle() {
  local target="$1" module_dir="$2" job=/tmp/job provider image
  bundle_load "$target"
  say "Building module for $target in isolated job $(basename "$job")"
  if [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 || "$OFFLINE" == 1 ]]; then :; fi
  case "$provider" in
    ubuntu|debian) run_container_root "$image" bash -lc "case x in x) : ;; esac" ;;
    fedora|centos) run_container_root "$image" true ;;
    rhel) if [[ -n "$image" ]]; then true; else true; fi ;;
    *) die "unsupported bundle provider '$provider'" ;;
  esac
}
reset_bundle_toolchain_vars(){ unset BUNDLE_TOOLCHAIN_BIN_DIR BUNDLE_TOOLCHAIN_ARCHIVE_SHA256; }
compiler_identity(){ :; }
prepare_bound_toolchain() {
  KLAB_TC_PATH="$PATH"; KLAB_TC_MAKE_ARGS=(); [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 ]] || return 0
  local cc="${BUNDLE_TOOLCHAIN_CC:-}" overridden=0 marker=""
  [[ -n "$cc" ]] || return 1
  if (( overridden == 0 )); then :; fi
  compiler_identity "$cc"
}
make_initramfs_bundle() { :; }
main() {
  local cmd="${1:-}"
  case "$cmd" in
    toolchain) shift; cmd_toolchain "$@" ;;
    *) : ;;
  esac
}
EOS
cat >"$T/src/klab-bundle.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LAB_HOME=/tmp/lab
KERNELS=/tmp/k
TOOLCHAINS=/tmp/t
KERNEL_LAB_BIN="$SELF_DIR/kernel-lab.sh"
detect_toolchain_cc(){ echo "$1/bin/gcc"; }
probe_toolchain_json(){ echo '{}'; }
sha256_file(){ echo deadbeef; }
add_checksum_line(){ :; }
write_manifest(){ :; }
cmd_create_legacy(){
  local stage=/tmp/stage toolchain=/tmp/tc toolchain_id=x toolchain_cc= toolchain_json
  write_manifest "$stage/manifest.json" x
  add_checksum_line "$stage" manifest.json
  if [[ -n "$toolchain" ]]; then
    say "Packing toolchain $(basename "$toolchain")"
    tar -C "$toolchain" --zstd -cf "$stage/extras/toolchain.tar.zst" .
    local tsha; tsha="$(sha256_file "$stage/extras/toolchain.tar.zst")"
    toolchain_json="$(probe_toolchain_json "$toolchain" "$tsha" "$toolchain_id" "$toolchain_cc")"
    add_checksum_line "$stage" extras/toolchain.tar.zst
  fi
}
quote_env(){ printf '%q' "$1"; }
json_get(){ echo ''; }
fixup_distro_env() {
  local dest="$1" manifest="$2" provider=test release=1 krel=k arch=x86_64 build_image='' build=/tmp source='' modules=''
  cat > "$dest/bundle.env" <<EOFENV
BUNDLE_PROVIDER=$(quote_env "$provider")
EOFENV
}
need_common(){ :; }
extract_outer(){ :; }
verify_stage(){ :; }
canonical_arch(){ echo "$1"; }
bundle_dir_for(){ echo /tmp/d; }
die(){ exit 1; }
cmd_import_legacy() {
  need_common
  local file="$1"; shift
  local force=0 load_image=0
  while (($#)); do
    case "$1" in --force) force=1;; --load-image) load_image=1;; *) die;; esac
    shift
  done
  local tmp; tmp="$(mktemp -d)"; trap "rm -rf '$tmp'" EXIT
  extract_outer "$file" "$tmp"
  verify_stage "$tmp"
  local kind=distro target=x provider=test release=1 krel=k profile=normal arch=x86_64 dest
  if [[ -f "$tmp/extras/toolchain.tar.zst" ]]; then
    local tc_id tc_sha tc_cc_rel tc_family tc_version tc_target tc_prefix_rel tc_bin_rel tc_dest
    tc_id="$(json_get "$tmp/manifest.json" toolchain.id 2>/dev/null || true)"
    tc_sha="$(json_get "$tmp/manifest.json" toolchain.sha256)"
    tc_cc_rel="$(json_get "$tmp/manifest.json" toolchain.cc_relpath 2>/dev/null || true)"
    tc_family="$(json_get "$tmp/manifest.json" toolchain.family 2>/dev/null || true)"
    tc_version="$(json_get "$tmp/manifest.json" toolchain.version 2>/dev/null || true)"
    tc_target="$(json_get "$tmp/manifest.json" toolchain.target 2>/dev/null || true)"
    tc_prefix_rel="$(json_get "$tmp/manifest.json" toolchain.cross_prefix_relpath 2>/dev/null || true)"
    tc_bin_rel="$(json_get "$tmp/manifest.json" toolchain.bin_dir_relpath 2>/dev/null || true)"
    tc_dest=/tmp/tc
    [[ -x "$tc_dest/$tc_cc_rel" ]] || die "bound compiler missing after import: $tc_dest/$tc_cc_rel"
    cat >> "$dest/bundle.env" <<EOFENV
BUNDLE_TOOLCHAIN_ARCHIVE_SHA256=$(quote_env "$tc_sha")
EOFENV
  fi
  if [[ "$kind" == distro ]]; then
    dest="$(bundle_dir_for "$provider" "$release" "$krel" "$arch")"
    if [[ -e "$dest" ]]; then
      (( force == 1 )) || die "destination already exists: $dest (use --force to replace)"
      rm -rf "$dest"
    fi
    mkdir -p "$dest"
    fixup_distro_env "$dest" "$tmp/manifest.json"
  elif [[ "$kind" == upstream ]]; then
    dest=/tmp/u
    if [[ -e "$dest" ]]; then
      (( force == 1 )) || die "destination already exists: $dest (use --force to replace)"
      rm -rf "$dest"
    fi
    mkdir -p "$dest/source" "$dest/build"
  fi
  printf '%s\n' "$dest"
}
EOS
chmod +x "$T/src/kernel-lab.sh" "$T/src/klab-bundle.sh"
"$ROOT/install-m2.sh" --check-only "$T/src" >/dev/null
# check-only must not modify target
! grep -q KLAB_PROVIDER_REFACTOR_M2 "$T/src/kernel-lab.sh" || { echo 'FAIL: check-only modified runner' >&2; exit 1; }
"$ROOT/install-m2.sh" "$T/src" >/dev/null
grep -q KLAB_PROVIDER_REFACTOR_M2 "$T/src/kernel-lab.sh"
grep -q KLAB_TOOLCHAIN_RUNTIME_BOUNDARY_M2 "$T/src/kernel-lab.sh"
grep -q KLAB_BUILDENV_TRANSFER_M2 "$T/src/klab-bundle.sh"
grep -q KLAB_TOOLCHAIN_BOUNDARY_M2 "$T/src/klab-bundle.sh"
[[ -x "$T/src/klab-buildenv.sh" && -x "$T/src/klab-toolchain-boundary.sh" ]]
find "$T/src" -maxdepth 1 -type d -name '.klab-m2-backup-*' | grep -q . || { echo 'FAIL: no installer backup' >&2; exit 1; }
# Root-aware helpers must ship with their shell and Python dependencies.
for f in klab klab-root lib/klab-root.sh lib/klab_paths.py lib/klab_distro_toolchain.py; do
  [[ -f "$T/src/$f" ]] || { echo "missing installed helper: $f" >&2; exit 1; }
done
KLAB_ROOT="$T/lab" KLAB_HOME= "$T/src/klab-buildenv.sh" list >/dev/null
KLAB_ROOT="$T/lab" KLAB_HOME= "$T/src/klab-distro-toolchain.sh" list >/dev/null
[[ -d "$T/lab/artifacts/buildenvs" && -d "$T/lab/artifacts/distro-toolchains" ]]
[[ ! -e "$T/lab/buildenvs" && ! -L "$T/lab/buildenvs" ]]
echo 'installer-smoke: PASS'
