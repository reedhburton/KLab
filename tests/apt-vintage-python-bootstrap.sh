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
    if [[ "$1" == bash && "${2:-}" == -lc ]]; then printf '%s\n' "$3" >"$T/generated.sh"; return 0; fi
    shift
  done
  return 1
}
source "$ROOT/lib/backends/apt.sh"
mkdir -p "$T/out"
( klab_backend_apt_capture_toolchain ubuntu 17.04 ubuntu:17.04 $'set -eu\nsuite=zesty\n:' "$T/out" x86_64 6.3.0 ) >/dev/null 2>&1 || true
[[ -s "$T/generated.sh" ]] || { echo 'FAIL: capture script not emitted' >&2; exit 1; }
bash -n "$T/generated.sh"
install_line=$(grep -n 'apt-get install.*cc_pkg.*binutils make python3' "$T/generated.sh" | head -n1 | cut -d: -f1)
first_python=$(grep -n 'python3 - <<' "$T/generated.sh" | head -n1 | cut -d: -f1)
[[ -n "$install_line" && -n "$first_python" && "$install_line" -lt "$first_python" ]] || { echo 'FAIL: python3 is not bootstrapped before guest-side use' >&2; exit 1; }
if grep -Eq 'subprocess\.(check_output|run)\([^\n]*text=True' "$T/generated.sh"; then
  echo 'FAIL: generated capture requires Python >=3.7 text= subprocess API' >&2; exit 1
fi
if grep -Eq 'subprocess\.run|subprocess\.DEVNULL' "$T/generated.sh"; then
  echo 'FAIL: generated capture requires Python newer than Ubuntu 12.04' >&2; exit 1
fi
grep -Fq 'universal_newlines=True' "$T/generated.sh" || { echo 'FAIL: old-Python-compatible subprocess decoding missing' >&2; exit 1; }
grep -Fq 'case "$a" in "$native"|all)' "$T/generated.sh" || { echo 'FAIL: APT capture retains foreign-architecture dependency alternatives' >&2; exit 1; }
grep -Fq 'dpkg -i /pkgs/*.deb' "$ROOT/lib/backends/apt.sh"
grep -Fq 'apt-get install -y -qq dpkg' "$ROOT/lib/backends/apt.sh"
echo 'apt-vintage-python-bootstrap: PASS'
