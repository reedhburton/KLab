#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/kernel-lab.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR="$(pwd)"
OFFLINE=0
SRC=/tmp/linux
ARCH=x86_64
providers_show() { echo old; }
provider_list_apt() { :; }
cmd_provider_list() {
  [[ "$OFFLINE" != 1 ]] || die "offline mode: provider listing requires network access"
  local spec="$1" pattern="${2:-}"
  [[ -z "$pattern" ]] || validate_token "$pattern" pattern
  parse_target "$spec"
  [[ -z "$KERNEL_RELEASE" ]] || die "list expects provider:release, not a kernel release"
  case "$PROVIDER" in
    ubuntu|debian) provider_list_apt "$PROVIDER" "$DISTRO_RELEASE" "$pattern" ;;
    fedora) provider_list_fedora "$DISTRO_RELEASE" "$pattern" ;;
    centos) provider_list_centos "$DISTRO_RELEASE" "$pattern" ;;
    rhel) provider_list_rhel "$DISTRO_RELEASE" "$pattern" ;;
    freebsd) provider_list_freebsd "$DISTRO_RELEASE" ;;
    upstream) git -C "$SRC" tag -l "v${pattern:-*}" | tail -n 200 ;;
    *) die "unknown provider '$PROVIDER'" ;;
  esac
}
extract_debs() { :; }
cmd_fetch() {
  local target="$1" bundle; parse_target "$target"
  case "$PROVIDER" in upstream|freebsd) return ;; esac
  bundle=/tmp/b
  case "$PROVIDER" in
    ubuntu|debian) fetch_apt_bundle "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$bundle" ;;
    fedora) fetch_fedora_bundle "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$bundle" ;;
    centos) fetch_centos_bundle "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$bundle" ;;
    rhel) fetch_rhel_bundle "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$bundle" ;;
    *) die "unknown provider '$PROVIDER'" ;;
  esac
}
cmd_info() { :; }
build_external_module_bundle() {
  local target="$1" module_dir="$2" job provider image
  if [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 || "$OFFLINE" == 1 ]]; then return; fi
  case "$provider" in
    ubuntu|debian) run_container_root "$image" bash -lc "case x in x) : ;; esac" ;;
    fedora|centos) run_container_root "$image" true ;;
    rhel) if [[ -n "$image" ]]; then true; else true; fi ;;
    *) die "unsupported bundle provider '$provider'" ;;
  esac
}
make_initramfs_bundle() { :; }
EOS
python3 "$ROOT/apply-provider-refactor.py" "$tmp/kernel-lab.sh" >/dev/null
bash -n "$tmp/kernel-lab.sh"
grep -q 'source "$SELF_DIR/lib/provider-core.sh"' "$tmp/kernel-lab.sh"
grep -q 'klab_provider_list "$PROVIDER"' "$tmp/kernel-lab.sh"
grep -q 'klab_provider_fetch "$PROVIDER"' "$tmp/kernel-lab.sh"
grep -q 'klab_provider_build_module "$provider"' "$tmp/kernel-lab.sh"
echo 'patcher-smoke: PASS'
