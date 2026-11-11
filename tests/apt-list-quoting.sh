#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
die(){ echo "apt-list-quoting: ERROR: $*" >&2; exit 1; }
# Execute the generated bash -lc command locally. setup supplies a fake apt-cache.
klab_provider_run_container(){ local provider="$1" image="$2"; shift 2; "$@"; }
source "$ROOT/lib/backends/apt.sh"
marker="$(mktemp)"; rm -f "$marker"; trap 'rm -f "$marker"' EXIT
setup='apt-cache(){
  case "$1" in
    dumpavail) printf "Package: linux-image-6.1.0-test-amd64\nVersion: 1.0\n\nPackage: linux-image-6.2.0-test-amd64\nVersion: 1.0\n\n" ;;
  esac
}'
malicious="6.1'; touch $marker; printf '"
out="$(klab_backend_apt_list debian mock "$setup" '^linux-image-[0-9].*-amd64$' "$malicious" || true)"
[[ ! -e "$marker" ]] || die 'APT list pattern executed shell content'
# Normal fixed-string filtering must still work.
out="$(klab_backend_apt_list debian mock "$setup" '^linux-image-[0-9].*-amd64$' '6.1.0')"
[[ "$out" == '6.1.0-test-amd64' ]] || die "unexpected filtered output: $out"
echo 'apt-list-quoting: PASS'
