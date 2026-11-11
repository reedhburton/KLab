#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export KLAB_ROOT="$T/lab" KLAB_R16_ENABLE_PANIC=0 KLAB_R16_MIXED_ARCH=0 KLAB_R16_MIXED_MATRIX=0 KLAB_R16_KERNEL_MATRIX=0
"$ROOT/klab-fault-overnight-r16.sh" >/dev/null
run="$(find "$KLAB_ROOT/results/logs/fault-overnight-r16" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | tail -n1)"
s="$KLAB_ROOT/results/logs/fault-overnight-r16/$run/summary.tsv"; [[ -f "$s" ]]; rows="$(wc -l < "$s")"; [[ "$rows" -ge 2 ]]
KLAB_R16_RESUME_RUN_ID=latest "$ROOT/klab-fault-overnight-r16.sh" >/dev/null
[[ "$(wc -l < "$s")" -eq "$rows" ]]
awk -F'\t' -v rows="$rows" 'NR>1{if($3!="SKIP_QEMU"&&$3!="SKIP_DISABLED"&&$3!="PASS"&&$3!="FAIL"&&$3!="TIMEOUT")exit 1} END{if(NR!=rows)exit 1}' "$s"
echo PASS
