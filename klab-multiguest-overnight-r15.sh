#!/usr/bin/env bash
# Resumable KLab multi-guest network scenario matrix (r15).
set -uo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB="${KLAB_MULTIGUEST_KLAB:-$SELF_DIR/kernel-lab.sh}"
KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"; export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"
RUN_BASE="$KLAB_ROOT/results/logs/multiguest-overnight"
ART_BASE="$KLAB_ROOT/results/multiguest-overnight"
TIMEOUT_SECS="${KLAB_MULTIGUEST_CASE_TIMEOUT:-21600}"
DO_MIXED="${KLAB_MULTIGUEST_MIXED_ARCH:-1}"
RESUME="${KLAB_MULTIGUEST_RESUME_RUN_ID:-}"
mkdir -p "$RUN_BASE" "$ART_BASE"
if [[ "$RESUME" == latest ]]; then RESUME="$(find "$RUN_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n1)"; fi
RUN_ID="${RESUME:-$(date -u +%Y%m%dT%H%M%SZ)}"; RUN_ROOT="$RUN_BASE/$RUN_ID"; mkdir -p "$RUN_ROOT/cases"
SUMMARY="$RUN_ROOT/summary.tsv"; [[ -f "$SUMMARY" ]] || printf 'case\tscenario\tresult\trc\tnote\n' > "$SUMMARY"
RESULT_TAR="$KLAB_ROOT/results/multiguest-overnight-${RUN_ID}-results.tar.gz"
completed(){ awk -F'\t' -v c="$1" 'NR>1&&$1==c&&$3!="RUNNING"{f=1} END{exit !f}' "$SUMMARY" 2>/dev/null; }
record(){ printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$SUMMARY"; }
qemu_ready(){
  local scenario="$1" arch q
  while IFS=$'\t' read -r _ _ arch _; do
    q="$($KLAB arch-plan "$arch" --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["execution"]["qemu_binary"] or "")' 2>/dev/null || true)"
    [[ -n "$q" && -x "$(command -v "$q" 2>/dev/null || true)" ]] || return 1
  done < <("$SELF_DIR/lib/multiguest_plan.py" guests "$scenario")
}
run_case(){
  local label="$1" rel="$2" scenario out rc result note
  scenario="$SELF_DIR/$rel"; out="$RUN_ROOT/cases/$label"
  if completed "$label"; then echo "SKIP completed $label"; return; fi
  mkdir -p "$out"
  if ! qemu_ready "$scenario"; then record "$label" "$rel" SKIP_QEMU 0 'required qemu-system binary missing'; echo "SKIP_QEMU $label"; return; fi
  echo "==> multi-guest case $label"
  set +e
  timeout --signal=TERM --kill-after=30 "$TIMEOUT_SECS" "$KLAB" multiguest-run "$scenario" --report-dir "$out" >"$out/runner.stdout" 2>"$out/runner.stderr"
  rc=$?
  set -e
  if ((rc==0)); then result=PASS; note='scenario completed'; elif ((rc==124||rc==137)); then result=TIMEOUT; note='case timeout'; else result=FAIL; note="scenario rc=$rc"; fi
  record "$label" "$rel" "$result" "$rc" "$note"
}
set -e
run_case simple-two-guest examples/multiguest/two-guest-network.json
run_case complex-kernel-span examples/multiguest/three-guest-kernel-span.json
if [[ "$DO_MIXED" == 1 ]]; then run_case complex-mixed-arch examples/multiguest/three-guest-mixed-arch.json; fi
{
 echo "KLab r15 multi-guest overnight $RUN_ID"; column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
} > "$RUN_ROOT/summary.txt"
tar -czf "$RESULT_TAR" -C "$RUN_ROOT" .
echo "$RESULT_TAR"
