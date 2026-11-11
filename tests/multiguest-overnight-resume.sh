#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export KLAB_ROOT="$T/lab" KLAB_MULTIGUEST_MIXED_ARCH=1
"$ROOT/klab-multiguest-overnight-r15.sh" >/dev/null
run="$(find "$KLAB_ROOT/results/logs/multiguest-overnight" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n1)"
s="$KLAB_ROOT/results/logs/multiguest-overnight/$run/summary.tsv"; [[ -f "$s" ]]; rows="$(wc -l < "$s")"; [[ "$rows" -eq 4 ]]
KLAB_MULTIGUEST_RESUME_RUN_ID=latest "$ROOT/klab-multiguest-overnight-r15.sh" >/dev/null
[[ "$(wc -l < "$s")" -eq "$rows" ]]
awk -F'\t' 'NR>1{if($3!="SKIP_QEMU"&&$3!="PASS"&&$3!="FAIL"&&$3!="TIMEOUT")exit 1} END{if(NR!=4)exit 1}' "$s"
echo PASS
