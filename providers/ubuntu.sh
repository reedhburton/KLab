#!/usr/bin/env bash
klab_provider_ubuntu_is_archived(){ local b="${1%%@*}" x; for x in ${KLAB_UBUNTU_ARCHIVED_RELEASES:-4.10 5.04 5.10 6.06 6.10 7.04 7.10 8.04 8.10 9.04 9.10 10.04 10.10 11.04 11.10 12.04 12.10 13.04 13.10 14.10 15.04 15.10 16.10 17.04 17.10 18.10 19.04 19.10 20.10 21.04 21.10 22.10 23.04 23.10 24.10 25.04 25.10}; do [[ "$b" == "$x" ]] && return 0; done; return 1; }
klab_provider_ubuntu_codename(){
  local b="${1%%@*}"
  case "$b" in
    4.10) echo warty;; 5.04) echo hoary;; 5.10) echo breezy;; 6.06) echo dapper;; 6.10) echo edgy;;
    7.04) echo feisty;; 7.10) echo gutsy;; 8.04) echo hardy;; 8.10) echo intrepid;; 9.04) echo jaunty;; 9.10) echo karmic;;
    10.04) echo lucid;; 10.10) echo maverick;; 11.04) echo natty;; 11.10) echo oneiric;; 12.04) echo precise;; 12.10) echo quantal;;
    13.04) echo raring;; 13.10) echo saucy;; 14.04) echo trusty;; 14.10) echo utopic;; 15.04) echo vivid;; 15.10) echo wily;;
    16.04) echo xenial;; 16.10) echo yakkety;; 17.04) echo zesty;; 17.10) echo artful;; 18.04) echo bionic;; 18.10) echo cosmic;;
    19.04) echo disco;; 19.10) echo eoan;; 20.04) echo focal;; 20.10) echo groovy;; 21.04) echo hirsute;; 21.10) echo impish;;
    22.04) echo jammy;; 22.10) echo kinetic;; 23.04) echo lunar;; 23.10) echo mantic;; 24.04) echo noble;; 24.10) echo oracular;;
    25.04) echo plucky;; 25.10) echo questing;; 26.04) echo resolute;;
    *) die "no Ubuntu codename mapping for release '$b'";;
  esac
}
klab_provider_ubuntu_setup(){
  local release="$1"
  if [[ "${ARCH:-x86_64}" == aarch64 ]]; then
    klab_provider_mirror_only && die "mirror-only: Ubuntu aarch64 requires an ARM64-specific KLAB_UBUNTU_APT_SOURCES_FILE"
    release_snapshot_parts "$release"
    [[ -z "$RELEASE_SNAPSHOT" ]] || die "Ubuntu aarch64 snapshot targets are not yet supported"
    klab_provider_ubuntu_is_archived "$release" && die "Ubuntu archived aarch64 targets are not yet supported"
    local suite; suite="$(klab_provider_ubuntu_codename "$release")"
    cat <<EOS
set -eu
dpkg --add-architecture arm64
mkdir -p /etc/apt/sources.list.d /var/lib/apt/lists/partial /var/cache/apt/archives/partial
rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources
cat >/etc/apt/sources.list <<EOSOURCES
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ $suite main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ $suite-updates main restricted universe multiverse
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ $suite-security main restricted universe multiverse
EOSOURCES
rm -rf /var/lib/apt/lists/*
apt-get update -qq
EOS
    return
  fi
  if klab_provider_mirror_only; then
    [[ "$release" != *@* ]] || die "mirror-only: Ubuntu @snapshot targets are disabled; mirror the desired snapshot into KLAB_UBUNTU_APT_SOURCES_FILE and use a non-@snapshot target"
    klab_provider_apt_mirror_setup
    return
  fi
  release_snapshot_parts "$release"
  if [[ -n "$RELEASE_SNAPSHOT" ]]; then apt_snapshot_setup_script ubuntu "$release"; return; fi
  if klab_provider_ubuntu_is_archived "$release"; then
    local suite
    suite="$(klab_provider_ubuntu_codename "$release")"
    cat <<EOS
set -eu
suite='$suite'
# Some historical Ubuntu OCI images omit APT state/config directories entirely.
# Recreate the standard directory skeleton before replacing repository metadata.
mkdir -p /etc/apt/sources.list.d /var/lib/apt/lists/partial /var/cache/apt/archives/partial
rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true
rm -rf /var/lib/apt/lists/*
mkdir -p /var/lib/apt/lists/partial
cat >/etc/apt/sources.list <<EOSOURCES
deb http://old-releases.ubuntu.com/ubuntu/ \$suite main restricted universe multiverse
deb http://old-releases.ubuntu.com/ubuntu/ \$suite-updates main restricted universe multiverse
deb http://old-releases.ubuntu.com/ubuntu/ \$suite-security main restricted universe multiverse
EOSOURCES
apt-get -o Acquire::Check-Valid-Until=false update -qq
EOS
  else printf 'apt-get update -qq\n'; fi
}
klab_provider_ubuntu_list(){ local r="$1" pat="${2:-}" img setup; img="$(provider_image ubuntu "$r")"; setup="$(klab_provider_ubuntu_setup "$r")"; say "Listing Ubuntu kernels from $r"; klab_backend_apt_list ubuntu "$img" "$setup" '^linux-image-[0-9].*-(generic|lowlatency|aws|azure|gcp|oracle|oem|realtime|gke)$' "$pat"; }
klab_provider_ubuntu_fetch(){ local r="$1" k="$2" b="$3" img setup; img="$(provider_image ubuntu "$r")"; setup="$(klab_provider_ubuntu_setup "$r")"; klab_backend_apt_fetch ubuntu "$r" "$k" "$b" "$img" "$setup"; }
klab_provider_ubuntu_build_module(){
  local r="$1" k="$2" img="$3" pkgs="$4" mod="$5" jobs="$6" build="${7:-}" arch="${8:-${ARCH:-x86_64}}"
  if [[ "$arch" == aarch64 ]]; then
    klab_backend_apt_cross_build_module "$k" "$mod" "$jobs" "$build" "$arch"
  else
    klab_backend_apt_build_module ubuntu "$img" "$(klab_provider_ubuntu_setup "$r")" "$pkgs" "$k" "$mod" "$jobs"
  fi
}
klab_provider_ubuntu_capture_buildenv(){ local r="$1" k="$2" b="$3" out="$4" arch="$5" img platform=""; img="$(provider_image ubuntu "$r")"; if [[ "$arch" == aarch64 ]]; then platform=linux/arm64; img="${KLAB_UBUNTU_AARCH64_IMAGE:-arm64v8/ubuntu:${r%%@*}}"; fi; KLAB_PROVIDER_CONTAINER_PLATFORM="$platform" klab_backend_apt_capture_buildenv ubuntu "$r" "$k" "$b" "$img" "$(klab_provider_ubuntu_setup "$r")" "$out" "$arch"; }
klab_provider_ubuntu_capture_toolchain(){ local r="$1" out="$2" arch="$3" compiler_version="${4:-}" img platform=""; img="$(provider_image ubuntu "$r")"; if [[ "$arch" == aarch64 ]]; then platform=linux/arm64; img="${KLAB_UBUNTU_AARCH64_IMAGE:-arm64v8/ubuntu:${r%%@*}}"; fi; KLAB_PROVIDER_CONTAINER_PLATFORM="$platform" klab_backend_apt_capture_toolchain ubuntu "$r" "$img" "$(klab_provider_ubuntu_setup "$r")" "$out" "$arch" "$compiler_version"; }
klab_provider_ubuntu_capabilities(){ local r="${1:-}" snaps=yes cross=no arches=x86_64; klab_provider_mirror_only && snaps=no; if [[ -n "$r" ]] && klab_provider_ubuntu_is_archived "$r"; then snaps=no; else cross=yes; arches=x86_64,aarch64; fi; printf 'list=yes fetch=yes build-module=yes buildenv=yes historical=yes snapshots=%s cross-arch=%s arches=%s\n' "$snaps" "$cross" "$arches"; }
klab_provider_ubuntu_describe(){ local r="${1:-}" state=current; [[ -n "$r" ]] && klab_provider_ubuntu_is_archived "$r" && state=archived; printf 'ubuntu    apt provider; %s%s\n' "$state" "${r:+ release $r}"; }
