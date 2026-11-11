#!/usr/bin/env bash
# KLab unified provider dispatcher, milestone 2.
# Provider policy lives in providers/*.sh; package mechanics in lib/backends/*.sh.
# v17 mirror-only policy is preserved here so provider adapters cannot bypass it.

KLAB_PROVIDER_ROOT="${KLAB_PROVIDER_ROOT:-$SELF_DIR/providers}"
KLAB_PROVIDER_BACKEND_ROOT="${KLAB_PROVIDER_BACKEND_ROOT:-$SELF_DIR/lib/backends}"

# Use the central architecture model when available so provider package-arch
# support and cross-staging policy are evaluated against the same canonical IDs
# as the core/QEMU/buildenv layers.
if [[ -f "${SELF_DIR:-.}/lib/arch-model.sh" ]]; then
  # shellcheck source=lib/arch-model.sh
  source "${SELF_DIR}/lib/arch-model.sh"
fi

klab_provider_mirror_only(){ [[ "${KLAB_MIRROR_ONLY:-0}" == 1 ]]; }
klab_provider_require_file(){ local p="$1" what="$2"; [[ -n "$p" && -f "$p" ]] || die "mirror-only: $what is required and must be a file"; }
klab_provider_require_dir(){ local p="$1" what="$2"; [[ -n "$p" && -d "$p" ]] || die "mirror-only: $what is required and must be a directory"; }

# Rootful and rootless Docker need different ownership values for writable
# bind mounts. In rootless Docker, container uid 0 maps to the invoking host
# user; chowning to the host numeric uid would map to a subordinate host uid.
klab_provider_container_is_rootless(){
  case "${KLAB_CONTAINER_ROOTLESS:-auto}" in
    1|yes|true) return 0 ;;
    0|no|false) return 1 ;;
    auto|'') ;;
    *) die "KLAB_CONTAINER_ROOTLESS must be auto, 0, or 1" ;;
  esac
  local rt base
  rt="$(container_runtime 2>/dev/null)" || return 1
  base="$(basename -- "$rt")"
  case "$base" in
    docker)
      "$rt" info --format '{{json .SecurityOptions}}' 2>/dev/null | grep -qi 'rootless' ;;
    podman)
      [[ "$("$rt" info --format '{{.Host.Security.Rootless}}' 2>/dev/null || true)" == true ]] ;;
    *)
      # Unknown runtimes may opt in/out explicitly with KLAB_CONTAINER_ROOTLESS.
      return 1 ;;
  esac
}
klab_provider_bind_output_owner(){
  if klab_provider_container_is_rootless; then
    printf '0:0\n'
  else
    printf '%s:%s\n' "${SUDO_UID:-$(id -u)}" "${SUDO_GID:-$(id -g)}"
  fi
}

klab_provider_prepare_mirror_args(){
  local provider="$1"
  KLAB_PROVIDER_MIRROR_ARGS=()
  klab_provider_mirror_only || return 0
  case "$provider" in
    ubuntu)
      klab_provider_require_file "${KLAB_UBUNTU_APT_SOURCES_FILE:-}" KLAB_UBUNTU_APT_SOURCES_FILE
      KLAB_PROVIDER_MIRROR_ARGS+=( -v "$KLAB_UBUNTU_APT_SOURCES_FILE:/klab-mirror/apt.sources.list:ro" ) ;;
    debian)
      klab_provider_require_file "${KLAB_DEBIAN_APT_SOURCES_FILE:-}" KLAB_DEBIAN_APT_SOURCES_FILE
      KLAB_PROVIDER_MIRROR_ARGS+=( -v "$KLAB_DEBIAN_APT_SOURCES_FILE:/klab-mirror/apt.sources.list:ro" ) ;;
    fedora)
      klab_provider_require_dir "${KLAB_FEDORA_REPOS_DIR:-}" KLAB_FEDORA_REPOS_DIR
      KLAB_PROVIDER_MIRROR_ARGS+=( -v "$KLAB_FEDORA_REPOS_DIR:/klab-mirror/repos:ro" ) ;;
    centos)
      klab_provider_require_dir "${KLAB_CENTOS_REPOS_DIR:-}" KLAB_CENTOS_REPOS_DIR
      KLAB_PROVIDER_MIRROR_ARGS+=( -v "$KLAB_CENTOS_REPOS_DIR:/klab-mirror/repos:ro" ) ;;
    rhel)
      [[ -n "${KLAB_RHEL_IMAGE:-}" ]] || die "mirror-only: RHEL requires explicit KLAB_RHEL_IMAGE; host RHSM/CDN fallback is disabled"
      klab_provider_require_dir "${KLAB_RHEL_REPOS_DIR:-}" KLAB_RHEL_REPOS_DIR
      KLAB_PROVIDER_MIRROR_ARGS+=( -v "$KLAB_RHEL_REPOS_DIR:/klab-mirror/repos:ro" ) ;;
    alpine)
      die "mirror-only: Alpine repository mounts are not implemented" ;;
    rocky)
      klab_provider_require_dir "${KLAB_ROCKY_REPOS_DIR:-}" KLAB_ROCKY_REPOS_DIR
      KLAB_PROVIDER_MIRROR_ARGS+=( -v "$KLAB_ROCKY_REPOS_DIR:/klab-mirror/repos:ro" ) ;;
    almalinux)
      klab_provider_require_dir "${KLAB_ALMALINUX_REPOS_DIR:-}" KLAB_ALMALINUX_REPOS_DIR
      KLAB_PROVIDER_MIRROR_ARGS+=( -v "$KLAB_ALMALINUX_REPOS_DIR:/klab-mirror/repos:ro" ) ;;
  esac
}

# Add only the provider-specific repository mount. provider_image()/the core
# container launcher remain responsible for the v17 image/registry policy.
klab_provider_run_container(){
  local provider="$1" image="$2"; shift 2
  klab_provider_prepare_mirror_args "$provider"
  local platform_args=()
  [[ -z "${KLAB_PROVIDER_CONTAINER_PLATFORM:-}" ]] || platform_args=(--platform "$KLAB_PROVIDER_CONTAINER_PLATFORM")
  run_container_root "$image" "${platform_args[@]}" "${KLAB_PROVIDER_MIRROR_ARGS[@]}" "$@"
}

klab_provider_apt_mirror_setup(){ cat <<'EOS'
set -eu
[ -f /klab-mirror/apt.sources.list ] || { echo 'mirror-only APT source list is not mounted' >&2; exit 45; }
mkdir -p /etc/apt/sources.list.d /var/lib/apt/lists/partial /var/cache/apt/archives/partial
rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true
cp /klab-mirror/apt.sources.list /etc/apt/sources.list
rm -rf /var/lib/apt/lists/*
mkdir -p /var/lib/apt/lists/partial
apt-get update -qq
EOS
}
klab_provider_dnf_mirror_setup(){ cat <<'EOS'
set -eu
[ -d /klab-mirror/repos ] || { echo 'mirror-only RPM repository directory is not mounted' >&2; exit 45; }
rm -f /etc/yum.repos.d/*.repo 2>/dev/null || true
cp /klab-mirror/repos/*.repo /etc/yum.repos.d/
dnf -q clean all >/dev/null 2>&1 || true
dnf -q makecache >/dev/null
EOS
}
klab_provider_yum_mirror_setup(){ cat <<'EOS'
set -eu
[ -d /klab-mirror/repos ] || { echo 'mirror-only RPM repository directory is not mounted' >&2; exit 45; }
rm -f /etc/yum.repos.d/*.repo 2>/dev/null || true
cp /klab-mirror/repos/*.repo /etc/yum.repos.d/
yum -q clean all >/dev/null 2>&1 || true
yum -q makecache >/dev/null
EOS
}

klab_provider_load_backends(){ local f; [[ -d "$KLAB_PROVIDER_BACKEND_ROOT" ]] || die "provider backend directory missing: $KLAB_PROVIDER_BACKEND_ROOT"; for f in "$KLAB_PROVIDER_BACKEND_ROOT"/*.sh; do [[ -f "$f" ]] || continue; source "$f"; done; [[ -f "$SELF_DIR/lib/buildenv-capture.sh" ]] && source "$SELF_DIR/lib/buildenv-capture.sh"; }
klab_provider_validate_kernel_release(){
  local k="$1"
  [[ "$k" =~ ^[A-Za-z0-9][A-Za-z0-9._+~-]*$ ]] || die "unsafe or invalid kernel release: $k"
}
klab_provider_validate_release(){
  local r="$1" base snap
  [[ -n "$r" ]] || die "provider release must not be empty"
  if [[ "$r" == *@* ]]; then
    [[ "$r" != *@*@* ]] || die "unsafe or invalid provider release: $r"
    base="${r%%@*}"; snap="${r#*@}"
    [[ "$base" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || die "unsafe or invalid provider release: $r"
    [[ "$snap" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || die "invalid provider snapshot timestamp: $snap (expected YYYYMMDDTHHMMSSZ)"
  else
    [[ "$r" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || die "unsafe or invalid provider release: $r"
  fi
}
klab_provider_canonical_arch(){
  if declare -F klab_arch_canonical >/dev/null 2>&1; then klab_arch_canonical "$1" 2>/dev/null || echo "$1"; return; fi
  case "$1" in
    x86_64|amd64) echo x86_64;; i386|i486|i586|i686|x86) echo i386;;
    aarch64|arm64) echo aarch64;; armv7|armv7l|armhf|arm) echo armv7;; mips|mipsel|mips64|mips64el) echo "$1";; *) echo "$1";;
  esac
}
klab_provider_capability_value(){
  local provider="$1" release="$2" key="$3" caps fn="klab_provider_${provider}_capabilities"
  declare -F "$fn" >/dev/null || return 1
  caps="$($fn "$release")"
  printf '%s\n' "$caps" | tr ' ' '\n' | sed -n "s/^${key}=//p" | head -n1
}
klab_provider_assert_snapshot(){
  local provider="$1" release="$2" mode
  [[ "$release" == *@* ]] || return 0
  mode="$(klab_provider_capability_value "$provider" "$release" snapshots || true)"
  [[ "$mode" == yes ]] || die "provider '$provider' does not support @timestamp snapshots (snapshots=${mode:-no})"
}
klab_provider_assert_arch(){
  local provider="$1" release="${2:-}" req="${3:-${ARCH:-x86_64}}" arches canon a ok=0 cross host
  arches="$(klab_provider_capability_value "$provider" "$release" arches || true)"
  canon="$(klab_provider_canonical_arch "$req")"
  if [[ -n "$arches" ]]; then
    IFS=',' read -r -a _klab_arches <<<"$arches"
    for a in "${_klab_arches[@]}"; do [[ "$canon" == "$(klab_provider_canonical_arch "$a")" ]] && ok=1; done
    (( ok == 1 )) || die "provider '$provider' does not support target architecture '$canon' (supported: $arches)"
  fi
  host="$(declare -F klab_arch_host >/dev/null 2>&1 && klab_arch_host || uname -m)"; host="$(klab_provider_canonical_arch "$host")"
  if [[ "$canon" != "$host" ]]; then
    cross="$(klab_provider_capability_value "$provider" "$release" cross-arch || true)"
    [[ "$cross" == yes ]] || die "provider '$provider' supports target '$canon' only from a same-architecture staging worker (build=$host target=$canon cross-arch=${cross:-no})"
  fi
}
klab_provider_validate_jobs(){
  local jobs="$1"
  [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || die "jobs must be a positive decimal integer: $jobs"
}
klab_provider_load(){
  local provider="$1" f="$KLAB_PROVIDER_ROOT/$1.sh" ef="$KLAB_PROVIDER_ROOT/experimental/$1.sh"
  if [[ -f "$f" ]]; then
    source "$f"
    return 0
  fi
  if [[ -f "$ef" ]]; then
    [[ "${KLAB_ENABLE_EXPERIMENTAL_PROVIDERS:-0}" == 1 ]] || \
      die "provider '$provider' is experimental; set KLAB_ENABLE_EXPERIMENTAL_PROVIDERS=1 to enable it"
    source "$ef"
    return 0
  fi
  die "provider '$provider' is not installed (expected $f)"
}
klab_provider_call(){
  local provider="$1" op="$2"; shift 2
  local fn="klab_provider_${provider}_${op}" release="${1:-}" req_arch="${ARCH:-x86_64}"
  klab_provider_load "$provider"
  declare -F "$fn" >/dev/null || die "provider '$provider' does not implement '$op'"
  [[ -z "$release" ]] || klab_provider_validate_release "$release"
  klab_provider_assert_snapshot "$provider" "$release"
  case "$op" in
    build_module) req_arch="${8:-${ARCH:-x86_64}}"; klab_provider_validate_jobs "${6:-}" ;;
    capture_buildenv) req_arch="${5:-${ARCH:-x86_64}}" ;;
    capture_toolchain) req_arch="${3:-${ARCH:-x86_64}}" ;;
  esac
  case "$op" in list|fetch|build_module|capture_buildenv|capture_toolchain) klab_provider_assert_arch "$provider" "$release" "$req_arch";; esac
  case "$op" in fetch|build_module|capture_buildenv) klab_provider_validate_kernel_release "${2:-}";; esac
  "$fn" "$@"
}
klab_provider_list(){ local p="$1" r="$2" pat="${3:-}"; klab_provider_call "$p" list "$r" "$pat"; }
klab_provider_fetch(){ local p="$1" r="$2" k="$3" b="$4"; klab_provider_call "$p" fetch "$r" "$k" "$b"; }
klab_provider_build_module(){ local p="$1" r="$2" k="$3" img="$4" pkgs="$5" mod="$6" jobs="$7" build="${8:-}" arch="${9:-${ARCH:-x86_64}}"; klab_provider_call "$p" build_module "$r" "$k" "$img" "$pkgs" "$mod" "$jobs" "$build" "$arch"; }
klab_provider_describe(){ klab_provider_call "$1" describe "${2:-}"; }
klab_provider_capabilities(){ klab_provider_call "$1" capabilities "${2:-}"; }
klab_provider_capture_buildenv(){ local p="$1" r="$2" k="$3" bundle="$4" out="$5" arch="${6:-${ARCH:-x86_64}}"; klab_provider_call "$p" capture_buildenv "$r" "$k" "$bundle" "$out" "$arch"; }
klab_provider_capture_toolchain(){ local p="$1" r="$2" out="$3" arch="${4:-${ARCH:-x86_64}}" compiler_version="${5:-}"; klab_provider_call "$p" capture_toolchain "$r" "$out" "$arch" "$compiler_version"; }
klab_provider_show(){ local f p; cat <<'EOS'
Providers:
  upstream  kernel.org source tags; built locally by kernel-lab
  freebsd   official FreeBSD release artifacts
EOS
  [[ -d "$KLAB_PROVIDER_ROOT" ]] || return 0
  for f in "$KLAB_PROVIDER_ROOT"/*.sh; do [[ -f "$f" ]] || continue; p="$(basename "$f" .sh)"; [[ "$p" == _template ]] && continue; klab_provider_load "$p"; local fn="klab_provider_${p}_describe"; declare -F "$fn" >/dev/null && "$fn" "" | sed 's/^/  /' || printf '  %-9s external provider\n' "$p"; done
  if [[ "${KLAB_ENABLE_EXPERIMENTAL_PROVIDERS:-0}" == 1 && -d "$KLAB_PROVIDER_ROOT/experimental" ]]; then
    for f in "$KLAB_PROVIDER_ROOT"/experimental/*.sh; do [[ -f "$f" ]] || continue; p="$(basename "$f" .sh)"; klab_provider_load "$p"; local fn="klab_provider_${p}_describe"; declare -F "$fn" >/dev/null && "$fn" "" | sed 's/^/  /' || printf '  %-9s experimental provider\n' "$p"; done
  fi
}
klab_provider_load_backends
