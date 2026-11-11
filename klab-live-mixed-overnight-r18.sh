#!/usr/bin/env bash
# KLab r18 live mixed-architecture routed matrix.
# Runs stable cases first, then experimental MIPS/MIPSel cases with their gates enabled.
set -uo pipefail

SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB="${KLAB_R18_KLAB:-$SELF_DIR/kernel-lab.sh}"
KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"
export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"
MATRIX="$SELF_DIR/examples/multiguest/mixed-matrix-r16/matrix.json"
RUN_BASE="$KLAB_ROOT/results/logs/live-mixed-overnight-r18"
REPORT_BASE="$KLAB_ROOT/results/live-mixed-overnight-r18"
CASE_TIMEOUT="${KLAB_R18_CASE_TIMEOUT:-14400}"
ENABLE_EXPERIMENTAL="${KLAB_R18_EXPERIMENTAL:-1}"
ENABLE_KERNEL_VARIANTS="${KLAB_R18_KERNEL_VARIANTS:-0}"
DRY_RUN="${KLAB_R18_DRY_RUN:-0}"
RESUME="${KLAB_R18_RESUME_RUN_ID:-}"
MIN_FREE_GIB="${KLAB_R18_MIN_FREE_GIB:-12}"

[[ -x "$KLAB" ]] || { echo "ERROR: KLab CLI is not executable: $KLAB" >&2; exit 2; }
[[ -f "$MATRIX" ]] || { echo "ERROR: matrix manifest missing: $MATRIX" >&2; exit 2; }
mkdir -p "$RUN_BASE" "$REPORT_BASE"
if [[ "$RESUME" == latest ]]; then
  RESUME="$(find "$RUN_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%f\n' 2>/dev/null | sort -nr | head -n1 | cut -f2-)"
fi
RUN_ID="${RESUME:-${KLAB_R18_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}}"
RUN_ROOT="$RUN_BASE/$RUN_ID"
REPORT_ROOT="$REPORT_BASE/$RUN_ID"
SUMMARY="$RUN_ROOT/summary.tsv"
RESULT_TAR="$KLAB_ROOT/results/live-mixed-overnight-r18-${RUN_ID}-results.tar.gz"
mkdir -p "$RUN_ROOT/cases" "$REPORT_ROOT"
[[ -f "$SUMMARY" ]] || printf 'case\tlane\tscenario\tresult\trc\tnote\treport\n' > "$SUMMARY"

fingerprint(){
  { sha256sum "$SELF_DIR/kernel-lab.sh" "$SELF_DIR/lib/multiguest-scenario.sh" "$SELF_DIR/lib/multiguest_plan.py" "$MATRIX"
    find "$SELF_DIR/examples/multiguest/mixed-matrix-r16" -maxdepth 2 -type f -name '*.json' -print0 | sort -z | xargs -0 sha256sum
  } | sha256sum | awk '{print $1}'
}
FP="$(fingerprint)"
if [[ -f "$RUN_ROOT/source.fingerprint" ]]; then
  old="$(cat "$RUN_ROOT/source.fingerprint")"
  [[ "$old" == "$FP" || "${KLAB_R18_ALLOW_SOURCE_CHANGE:-0}" == 1 ]] || {
    echo "ERROR: resume refused because source/scenario fingerprint changed: $old -> $FP" >&2
    exit 72
  }
else
  printf '%s\n' "$FP" > "$RUN_ROOT/source.fingerprint"
fi

completed(){ awk -F '\t' -v c="$1" 'NR>1 && $1==c && $4!="RUNNING" {f=1} END{exit !f}' "$SUMMARY" 2>/dev/null; }
record(){ printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" >> "$SUMMARY"; }
scenario_arches(){ "$SELF_DIR/lib/multiguest_plan.py" guests "$1" | awk -F '\t' '{print $3}' | sort -u; }
qemu_for_arch(){ "$KLAB" arch-plan "$1" --kernel v6.6 --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["execution"]["qemu_binary"] or "")'; }
preflight_case(){
  local scenario="$1" arch q missing=0
  while IFS= read -r arch; do
    [[ -n "$arch" ]] || continue
    q="$(qemu_for_arch "$arch" 2>/dev/null || true)"
    if [[ -z "$q" || -z "$(command -v "$q" 2>/dev/null || true)" ]]; then
      echo "missing QEMU for $arch: ${q:-unresolved}"
      missing=1
    else
      printf '%s\t%s\t%s\n' "$arch" "$q" "$($q --version 2>/dev/null | head -n1)"
    fi
  done < <(scenario_arches "$scenario")
  return "$missing"
}

run_case(){
  local lane="$1" rel="$2" label scenario out rc result note preflight
  label="${lane}-${rel%.json}"
  scenario="$SELF_DIR/examples/multiguest/mixed-matrix-r16/$rel"
  out="$REPORT_ROOT/$label"
  completed "$label" && { echo "SKIP completed $label"; return 0; }
  mkdir -p "$out"
  preflight="$RUN_ROOT/cases/$label.preflight"
  if ! preflight_case "$scenario" >"$preflight" 2>&1; then
    record "$label" "$lane" "$rel" SKIP_QEMU 127 'required qemu-system binary missing' "$out"
    return 0
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    set +e
    if [[ "$lane" == experimental ]]; then
      env KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 KLAB_ENABLE_EXPERIMENTAL_E2E=1 "$KLAB" multiguest-run "$scenario" --report-dir "$out" --dry-run >"$RUN_ROOT/cases/$label.stdout" 2>"$RUN_ROOT/cases/$label.stderr"
    else
      "$KLAB" multiguest-run "$scenario" --report-dir "$out" --dry-run >"$RUN_ROOT/cases/$label.stdout" 2>"$RUN_ROOT/cases/$label.stderr"
    fi
    rc=$?; set -e
    [[ $rc -eq 0 ]] && result=PLANNED || result=MODEL_FAIL
    record "$label" "$lane" "$rel" "$result" "$rc" dry-run "$out"
    return 0
  fi
  echo "==> KLab r18 $lane case: $rel"
  record "$label" "$lane" "$rel" RUNNING 0 started "$out"
  set +e
  if [[ "$lane" == experimental ]]; then
    timeout --signal=TERM --kill-after=60 "$CASE_TIMEOUT" env KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 KLAB_ENABLE_EXPERIMENTAL_E2E=1 "$KLAB" multiguest-run "$scenario" --report-dir "$out" >"$RUN_ROOT/cases/$label.stdout" 2>"$RUN_ROOT/cases/$label.stderr"
  else
    timeout --signal=TERM --kill-after=60 "$CASE_TIMEOUT" "$KLAB" multiguest-run "$scenario" --report-dir "$out" >"$RUN_ROOT/cases/$label.stdout" 2>"$RUN_ROOT/cases/$label.stderr"
  fi
  rc=$?; set -e
  if (( rc == 0 )); then result=PASS; note=completed
  elif (( rc == 124 || rc == 137 )); then result=TIMEOUT; note="timeout-${CASE_TIMEOUT}s"
  else result=FAIL; note="rc=$rc"
  fi
  record "$label" "$lane" "$rel" "$result" "$rc" "$note" "$out"
}

set -e
free_kib="$(df -Pk "$KLAB_ROOT" | awk 'NR==2{print $4}')"
required_kib=$((MIN_FREE_GIB * 1024 * 1024))
if (( free_kib < required_kib )); then
  echo "ERROR: only $((free_kib/1024/1024)) GiB free under $KLAB_ROOT; require ${MIN_FREE_GIB} GiB" >&2
  exit 74
fi
printf 'run_id=%s\nroot=%s\nfree_gib=%s\ncase_timeout=%s\nexperimental=%s\nkernel_variants=%s\n' \
  "$RUN_ID" "$KLAB_ROOT" "$((free_kib/1024/1024))" "$CASE_TIMEOUT" "$ENABLE_EXPERIMENTAL" "$ENABLE_KERNEL_VARIANTS" > "$RUN_ROOT/run.env"

bash "$SELF_DIR/tests/multiguest-r16-model.sh" >"$RUN_ROOT/model-test.log" 2>&1
bash "$SELF_DIR/tests/r16-mixed-arch-matrix.sh" >"$RUN_ROOT/matrix-test.log" 2>&1

while IFS= read -r rel; do [[ -n "$rel" ]] && run_case stable "$rel"; done < <(
  python3 - "$MATRIX" <<'PY'
import json,sys
for value in json.load(open(sys.argv[1]))['stable']:
    print(value)
PY
)

if [[ "$ENABLE_EXPERIMENTAL" == 1 ]]; then
  while IFS= read -r rel; do [[ -n "$rel" ]] && run_case experimental "$rel"; done < <(
    python3 - "$MATRIX" <<'PY'
import json,sys
for value in json.load(open(sys.argv[1]))['experimental']:
    print(value)
PY
  )
fi

if [[ "$ENABLE_KERNEL_VARIANTS" == 1 ]]; then
  while IFS= read -r rel; do [[ -n "$rel" ]] && run_case kernel "$rel"; done < <(
    python3 - "$MATRIX" <<'PY'
import json,sys
for value in json.load(open(sys.argv[1])).get('kernel_variants',{}).get('stable',[]):
    print('kernel-variants/'+value)
PY
  )
fi

{
  echo "KLab r18 live mixed-architecture overnight: $RUN_ID"
  echo "Root: $KLAB_ROOT"
  echo "Experimental MIPS/MIPSel: $ENABLE_EXPERIMENTAL"
  echo "Kernel variants: $ENABLE_KERNEL_VARIANTS"
  echo
  awk -F '\t' 'NR>1 && $4!="RUNNING" {c[$4]++} END{for(k in c) print k, c[k]}' "$SUMMARY" | sort
  echo
  awk -F '\t' 'NR==1 || ($4!="PASS" && $4!="PLANNED" && $4!="RUNNING")' "$SUMMARY"
} > "$RUN_ROOT/REVIEW-ME.txt"
awk -F '\t' 'NR==1 || $4!="RUNNING"' "$SUMMARY" > "$RUN_ROOT/summary.final.tsv"
(
  cd "$KLAB_ROOT/results"
  { find "logs/live-mixed-overnight-r18/$RUN_ID" -type f -print; find "live-mixed-overnight-r18/$RUN_ID" -type f ! -name '*.klab' -print; } | tar -czf "$RESULT_TAR" -T - 2>/dev/null || true
)
printf 'Results: %s\n' "$RESULT_TAR"
