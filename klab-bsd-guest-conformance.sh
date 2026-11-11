#!/usr/bin/env bash
set -euo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"; KLAB_BIN="${KLAB_BIN:-$SELF/kernel-lab.sh}"; KLAB_ROOT="${KLAB_ROOT:-$HOME/klab}"
[[ $# -eq 2 ]] || { echo 'usage: klab-bsd-guest-conformance.sh SESSION REPORT_DIR' >&2; exit 2; }
session="$1"; report="$2"; mkdir -p "$report"; results="$report/results.tsv"; printf 'CAPABILITY\tRESULT\tEVIDENCE\n' >"$results"; failures=0
probe(){ local n="$1" c="$2" e rc; e="$report/$n.log"; set +e; KLAB_ROOT="$KLAB_ROOT" "$KLAB_BIN" exec "$session" "$c" >"$e" 2>&1; rc=$?; set -e; if ((rc==0)); then printf '%s\tPASS\t%s\n' "$n" "$e" >>"$results"; else printf '%s\tFAIL\t%s\n' "$n" "$e" >>"$results"; failures=$((failures+1)); fi; }
probe identity 'freebsd-version; uname -a; uname -m'
probe filesystem 'set -eu; p=/tmp/klab-bsd-$$; mkdir "$p"; echo data >"$p/file"; test "$(cat "$p/file")" = data; mv "$p/file" "$p/moved"; rm -rf "$p"'
probe kernel_interfaces 'set -eu; sysctl kern.osrelease kern.ostype hw.machine; test -c /dev/null'
probe processes 'set -eu; (sleep 1; echo one) & a=$!; (sleep 1; echo two) & b=$!; wait "$a"; wait "$b"; echo x | grep -qx x'
probe toolchain 'set -eu; command -v cc; command -v make; d=/tmp/klab-cc-$$; mkdir "$d"; echo "int main(void){return 0;}" >"$d/a.c"; cc "$d/a.c" -o "$d/a"; "$d/a"; rm -rf "$d"'
probe runtime 'set -eu; ldd /bin/sh; /bin/sh -c "exit 0"'
probe networking 'set -eu; ifconfig vtnet0; ifconfig vtnet0 | grep -q "inet 10.0.2."; ping -c 1 10.0.2.2'
probe modules 'set -eu; command -v kldstat; kldstat'
probe shutdown_path 'set -eu; command -v sync; command -v shutdown; command -v reboot'
[[ "$failures" == 0 ]] && result=PASS || result=FAIL; echo "$result" >"$report/RESULT"; echo "KLab BSD guest conformance: $result ($failures failures)"; ((failures==0))
