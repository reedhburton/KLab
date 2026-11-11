#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
for F in "$ROOT/kernel-lab.sh" "$ROOT/lib/backends/apt.sh"; do
  grep -Fq 'apt-cache dumpavail' "$F" || { echo "FAIL: Ubuntu catalog does not use one repository availability scan: $F" >&2; exit 1; }
  if grep -Fq 'while read -r p; do apt-cache policy' "$F" || grep -Fq 'for p in $(apt-cache pkgnames' "$F"; then
    echo "FAIL: Ubuntu catalog still performs one apt-cache policy process per package: $F" >&2; exit 1
  fi
  grep -Fq 'tail -n 2000' "$F" || { echo "FAIL: Ubuntu catalog output cap is too small for fine-grained ABI enumeration: $F" >&2; exit 1; }
done
echo 'PASS: Ubuntu catalog uses a bounded single-pass availability scan'
