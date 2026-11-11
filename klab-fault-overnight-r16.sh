#!/usr/bin/env bash
# Resumable KLab topology/fault scenario matrix (r16).
set -uo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB="${KLAB_R16_KLAB:-$SELF_DIR/kernel-lab.sh}"
KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"; export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"
RUN_BASE="$KLAB_ROOT/results/logs/fault-overnight-r16"
TIMEOUT_SECS="${KLAB_R16_CASE_TIMEOUT:-21600}"
DO_PANIC="${KLAB_R16_ENABLE_PANIC:-0}"
DO_MIXED="${KLAB_R16_MIXED_ARCH:-1}"
DO_MIXED_MATRIX="${KLAB_R16_MIXED_MATRIX:-1}"
DO_EXPERIMENTAL_MATRIX="${KLAB_R16_EXPERIMENTAL_MATRIX:-0}"
DO_KERNEL_MATRIX="${KLAB_R16_KERNEL_MATRIX:-1}"
RESUME="${KLAB_R16_RESUME_RUN_ID:-}"
mkdir -p "$RUN_BASE"
if [[ "$RESUME" == latest ]]; then RESUME="$(find "$RUN_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | tail -n1)"; fi
RUN_ID="${RESUME:-$(date -u +%Y%m%dT%H%M%SZ)}"; RUN_ROOT="$RUN_BASE/$RUN_ID"; mkdir -p "$RUN_ROOT/cases"
SUMMARY="$RUN_ROOT/summary.tsv"; [[ -f "$SUMMARY" ]] || printf 'case\tscenario\tresult\trc\tnote\n' > "$SUMMARY"
RESULT_TAR="$KLAB_ROOT/results/fault-overnight-r16-${RUN_ID}-results.tar.gz"
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
  echo "==> r16 topology/fault case $label"
  set +e
  timeout --signal=TERM --kill-after=30 "$TIMEOUT_SECS" "$KLAB" multiguest-run "$scenario" --report-dir "$out" >"$out/runner.stdout" 2>"$out/runner.stderr"
  rc=$?
  set -e
  if ((rc==0)); then result=PASS; note='scenario completed'; elif ((rc==124||rc==137)); then result=TIMEOUT; note='case timeout'; else result=FAIL; note="scenario rc=$rc"; fi
  record "$label" "$rel" "$result" "$rc" "$note"
}
set -e
run_case routed-two-lan examples/multiguest/two-lan-router-r16.json
run_case link-flap-recovery examples/multiguest/link-flap-recovery-r16.json
run_case process-failure examples/multiguest/process-failure-r16.json
run_case guest-power-cut examples/multiguest/guest-power-cut-r16.json
if [[ "$DO_MIXED" == 1 ]]; then run_case routed-mixed-arch examples/multiguest/routed-mixed-arch-r16.json; fi
if [[ "$DO_MIXED_MATRIX" == 1 ]]; then
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    run_case "matrix-${rel%.json}" "examples/multiguest/mixed-matrix-r16/$rel"
  done < <(python3 - "$SELF_DIR/examples/multiguest/mixed-matrix-r16/matrix.json" <<'PYM'
import json,sys
for x in json.load(open(sys.argv[1]))["stable"]: print(x)
PYM
)
fi
if [[ "$DO_KERNEL_MATRIX" == 1 ]]; then
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    run_case "kernel-${rel%.json}" "examples/multiguest/mixed-matrix-r16/kernel-variants/$rel"
  done < <(python3 - "$SELF_DIR/examples/multiguest/mixed-matrix-r16/matrix.json" <<'PYK'
import json,sys
for x in json.load(open(sys.argv[1])).get("kernel_variants",{}).get("stable",[]): print(x)
PYK
)
else
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    completed "kernel-${rel%.json}" || record "kernel-${rel%.json}" "examples/multiguest/mixed-matrix-r16/kernel-variants/$rel" SKIP_DISABLED 0 'kernel-version matrix disabled'
  done < <(python3 - "$SELF_DIR/examples/multiguest/mixed-matrix-r16/matrix.json" <<'PYK'
import json,sys
for x in json.load(open(sys.argv[1])).get("kernel_variants",{}).get("stable",[]): print(x)
PYK
)
fi
if [[ "$DO_EXPERIMENTAL_MATRIX" == 1 ]]; then
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    run_case "matrix-exp-${rel%.json}" "examples/multiguest/mixed-matrix-r16/$rel"
  done < <(python3 - "$SELF_DIR/examples/multiguest/mixed-matrix-r16/matrix.json" <<'PYM'
import json,sys
for x in json.load(open(sys.argv[1]))["experimental"]: print(x)
PYM
)
else
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    completed "matrix-exp-${rel%.json}" || record "matrix-exp-${rel%.json}" "examples/multiguest/mixed-matrix-r16/$rel" SKIP_DISABLED 0 'experimental matrix disabled'
  done < <(python3 - "$SELF_DIR/examples/multiguest/mixed-matrix-r16/matrix.json" <<'PYM'
import json,sys
for x in json.load(open(sys.argv[1]))["experimental"]: print(x)
PYM
)
fi
if [[ "$DO_PANIC" == 1 ]]; then run_case kernel-panic examples/multiguest/kernel-panic-r16.json; fi
{
 echo "KLab r16 topology/fault overnight $RUN_ID"; column -t -s $'\t' "$SUMMARY" 2>/dev/null || cat "$SUMMARY"
} > "$RUN_ROOT/summary.txt"
tar -czf "$RESULT_TAR" -C "$RUN_ROOT" .
echo "$RESULT_TAR"
