#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repos"; printf 'deb https://apt.internal.invalid/ubuntu zesty main\n' >"$T/ubuntu.list"; printf '[internal]\nbaseurl=https://rpm.internal.invalid/centos\nenabled=1\ngpgcheck=0\n' >"$T/repos/internal.repo"
SELF_DIR="$ROOT"; ARCH=x86_64; KLAB_MIRROR_ONLY=1; KLAB_UBUNTU_APT_SOURCES_FILE="$T/ubuntu.list"; KLAB_CENTOS_REPOS_DIR="$T/repos"
die(){ echo "DIE:$*" >&2; exit 97; }
say(){ :; }
provider_image(){ printf '%s:%s\n' "$1" "${2%%@*}"; }
release_snapshot_parts(){ RELEASE_BASE="${1%%@*}"; RELEASE_SNAPSHOT=''; [[ "$1" == *@* ]] && RELEASE_SNAPSHOT="${1#*@}"; }
apt_snapshot_setup_script(){ echo PUBLIC-SNAPSHOT-SHOULD-NOT-RUN; }
run_container_root(){ printf '%q ' "$@" >"$T/container.args"; printf '\n' >>"$T/container.args"; }
write_package_manifest(){ :; }; extract_debs(){ :; }; normalize_bundle(){ :; }; extract_rpms(){ :; }
source "$ROOT/lib/provider-core.sh"
source "$ROOT/providers/ubuntu.sh"
source "$ROOT/providers/centos.sh"

u="$(klab_provider_ubuntu_setup 17.04)"
[[ "$u" == *'/klab-mirror/apt.sources.list'* ]] || { echo 'FAIL: archived Ubuntu mirror setup does not use mounted internal source' >&2; exit 1; }
[[ "$u" != *old-releases.ubuntu.com* ]] || { echo 'FAIL: archived Ubuntu leaked public old-releases in mirror-only' >&2; exit 1; }
if (klab_provider_ubuntu_setup '22.04@20250101T000000Z') >/dev/null 2>&1; then echo 'FAIL: Ubuntu snapshot allowed in mirror-only' >&2; exit 1; fi

c="$(klab_provider_centos7_setup)"
[[ "$c" == *'/klab-mirror/repos'* ]] || { echo 'FAIL: CentOS 7 mirror setup does not use mounted internal repos' >&2; exit 1; }
[[ "$c" != *vault.centos.org* ]] || { echo 'FAIL: CentOS 7 leaked public Vault in mirror-only' >&2; exit 1; }

klab_provider_run_container ubuntu ubuntu:17.04 bash -lc true
args="$(cat "$T/container.args")"
[[ "$args" == *"$T/ubuntu.list:/klab-mirror/apt.sources.list:ro"* ]] || { echo 'FAIL: Ubuntu internal source was not mounted' >&2; cat "$T/container.args" >&2; exit 1; }
klab_provider_run_container centos centos:7 bash -lc true
args="$(cat "$T/container.args")"
[[ "$args" == *"$T/repos:/klab-mirror/repos:ro"* ]] || { echo 'FAIL: CentOS internal repos were not mounted' >&2; cat "$T/container.args" >&2; exit 1; }

# Fail closed when mirror policy is enabled but provider config is missing.
unset KLAB_UBUNTU_APT_SOURCES_FILE
if (klab_provider_run_container ubuntu ubuntu:17.04 true) >/dev/null 2>&1; then echo 'FAIL: Ubuntu mirror-only ran without source list' >&2; exit 1; fi
unset KLAB_CENTOS_REPOS_DIR
if (klab_provider_run_container centos centos:7 true) >/dev/null 2>&1; then echo 'FAIL: CentOS mirror-only ran without repo directory' >&2; exit 1; fi

echo 'provider-mirror-policy: PASS'
