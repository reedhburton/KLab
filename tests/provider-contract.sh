#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; SELF_DIR="$ROOT"; die(){ echo "FAIL: $*" >&2; exit 1; }; say(){ :; }
run_container_root(){ printf 'MOCK_CONTAINER %q' "$1"; shift; printf ' %q' "$@"; printf '\n'; }
provider_image(){ printf '%s:%s\n' "$1" "${2%%@*}"; }
release_snapshot_parts(){ RELEASE_BASE="${1%%@*}"; RELEASE_SNAPSHOT=''; [[ "$1" == *@* ]] && RELEASE_SNAPSHOT="${1#*@}"; }
apt_snapshot_setup_script(){ printf 'apt-get update -qq\n'; }
write_package_manifest(){ :; }; extract_debs(){ :; }; extract_rpms(){ :; }; normalize_bundle(){ :; }
ARCH=x86_64
source "$ROOT/lib/provider-core.sh"
grep -Fq 'KLAB_FEDORA_KOJI_IMAGE:-fedora:43' "$ROOT/kernel-lab.sh" || die 'Fedora historical Koji discovery is tied to release OCI images'
for p in ubuntu debian centos fedora rhel; do klab_provider_load "$p"; for op in list fetch build_module capture_buildenv describe capabilities; do declare -F "klab_provider_${p}_${op}" >/dev/null || die "$p missing $op"; done; done
( klab_provider_load rocky ) >/dev/null 2>&1 && die 'experimental Rocky provider loaded without opt-in' || true
KLAB_ENABLE_EXPERIMENTAL_PROVIDERS=1 klab_provider_load rocky
declare -F klab_provider_rocky_describe >/dev/null || die 'experimental Rocky provider opt-in failed'
KLAB_ENABLE_EXPERIMENTAL_PROVIDERS=1 klab_provider_load almalinux
declare -F klab_provider_almalinux_describe >/dev/null || die 'experimental AlmaLinux provider opt-in failed'
u="$(klab_provider_ubuntu_setup 17.04)"; grep -q old-releases.ubuntu.com <<<"$u" || die 'Ubuntu 17.04 not deterministic archive'; ! grep -q 'if ! apt-get update' <<<"$u" || die 'Ubuntu archive selection is still reactive'; grep -q "suite='zesty'" <<<"$u" || die 'Ubuntu 17.04 codename is not pinned to zesty'; ! grep -q 'VERSION_CODENAME' <<<"$u" || die 'Ubuntu archived setup still depends on container os-release codename'
c="$(klab_provider_centos7_setup)"; grep -q 'vault.centos.org/7.9.2009' <<<"$c" || die 'CentOS Vault missing'; klab_provider_centos_is_v7 7 || die 'CentOS 7 selector'; ! klab_provider_centos_is_v7 stream9 || die 'Stream misdetected'
cap="$(klab_provider_capabilities ubuntu 17.04)"; grep -q 'buildenv=yes' <<<"$cap" || die 'Ubuntu buildenv capability missing'; grep -q 'cross-arch=no' <<<"$cap" || die 'capability overstates cross-arch'
out="$(klab_provider_list ubuntu 17.04 4.10)"; grep -q old-releases.ubuntu.com <<<"$out" || die 'Ubuntu routing missing archive'
bs="$(klab_provider_debian_setup bullseye)"; grep -q snapshot.debian.org <<<"$bs" || die 'Bullseye is not pinned to its authenticated OCI snapshot'; grep -q 'cat >/etc/apt/sources.list' <<<"$bs" || die 'Bullseye snapshot does not replace live sources atomically'
grep -Fq '\([^/[:space:]]*\)[/[:space:]]' <<<"$bs" || die 'Bullseye snapshot parser does not accept current OCI whitespace-separated timestamp hints'
out="$(klab_provider_list centos 7 3.10)"; grep -q vault.centos.org <<<"$out" || die 'CentOS routing missing Vault'; grep -q yum <<<"$out" || die 'CentOS routing missing yum'
echo 'provider-contract: PASS'
echo 'provider-routing: PASS'
