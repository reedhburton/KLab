#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
say(){ :; }
die(){ return 1; }
klab_provider_bind_output_owner(){ printf '1000:1000\n'; }
klab_provider_run_container(){
  local provider="$1" image="$2"; shift 2
  while (($#)); do
    if [[ "$1" == bash && "${2:-}" == -lc ]]; then
      printf '%s\n' "$3" >"$T/generated.sh"
      return 0
    fi
    shift
  done
  return 1
}
# shellcheck source=../lib/backends/apt.sh
source "$ROOT/lib/backends/apt.sh"
mkdir -p "$T/out"
( klab_backend_apt_capture_toolchain ubuntu 17.04 ubuntu:17.04 $'set -eu\nsuite=zesty\n:' "$T/out" x86_64 6.3.0 ) >/dev/null 2>&1 || true
[[ -s "$T/generated.sh" ]] || { echo 'FAIL: APT distro-toolchain capture did not emit container script' >&2; exit 1; }
bash -n "$T/generated.sh" || { echo 'FAIL: generated APT distro-toolchain capture script is not valid shell' >&2; exit 1; }
grep -Fq 'stanza=$(apt-cache show "$p=$v"' "$T/generated.sh" || { echo 'FAIL: package-metadata stanza command was mangled during shell generation' >&2; exit 1; }
grep -Fq '[ -n "$stanza" ]' "$T/generated.sh" || { echo 'FAIL: generated stanza validation lost quoting' >&2; exit 1; }
echo 'apt-capture-script-quoting: PASS'
