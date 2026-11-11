#!/usr/bin/env bash
# KLab r14 coordinated multi-process scenario matrix.
# Reuses one scenario across kernel versions and architectures.
set -uo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB="${KLAB_SCENARIO_KLAB:-$SELF_DIR/kernel-lab.sh}"
[[ -x "$KLAB" ]] || { echo "ERROR: KLab CLI not found: $KLAB" >&2; exit 2; }
KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"; export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"
TEMPLATE="${KLAB_SCENARIO_TEMPLATE:-$SELF_DIR/examples/scenarios/multiprocess-basic.json}"
ARCHES="${KLAB_SCENARIO_ARCHES:-x86_64 i386 aarch64 armv7}"
ENABLE_MIPS="${KLAB_SCENARIO_ENABLE_MIPS:-0}"
if [[ "$ENABLE_MIPS" == 1 ]]; then
  [[ " $ARCHES " == *" mips "* ]] || ARCHES="$ARCHES mips"
  [[ " $ARCHES " == *" mipsel "* ]] || ARCHES="$ARCHES mipsel"
fi
VERSIONS_DEFAULT="${KLAB_SCENARIO_VERSIONS:-v5.15 v6.6 v7.0}"
TIMEOUT="${KLAB_SCENARIO_CASE_TIMEOUT:-10800}"
RESUME="${KLAB_SCENARIO_RESUME_RUN_ID:-}"
latest_run(){ local base="$KLAB_ROOT/results/logs/scenario-matrix"; [[ -d "$base" ]] || return 1; find "$base" -mindepth 1 -maxdepth 1 -type d -printf '%T@\t%f\n' 2>/dev/null | sort -nr | head -n1 | cut -f2-; }
[[ "$RESUME" == latest ]] && RESUME="$(latest_run || true)"
RUN_ID="${RESUME:-${KLAB_SCENARIO_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}}"
RUN_ROOT="$KLAB_ROOT/results/logs/scenario-matrix/$RUN_ID"
REPORT_ROOT="$KLAB_ROOT/results/scenario-matrix/$RUN_ID"
SUMMARY="$RUN_ROOT/summary.tsv"; RESULT_TAR="$KLAB_ROOT/results/scenario-matrix-${RUN_ID}-results.tar.gz"
mkdir -p "$RUN_ROOT/generated" "$REPORT_ROOT"
[[ -f "$SUMMARY" ]] || printf 'arch\ttarget\trc\tstatus\treport\n' > "$SUMMARY"
case_done(){ awk -F '\t' -v a="$1" -v t="$2" 'NR>1&&$1==a&&$2==t{f=1}END{exit f?0:1}' "$SUMMARY"; }
record(){ printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$SUMMARY"; }
versions_for_arch(){ local a="$1" v=''; case "$a" in x86_64) v="${KLAB_SCENARIO_X86_64_VERSIONS:-}";; i386) v="${KLAB_SCENARIO_I386_VERSIONS:-}";; aarch64) v="${KLAB_SCENARIO_AARCH64_VERSIONS:-}";; armv7) v="${KLAB_SCENARIO_ARMV7_VERSIONS:-}";; mips) v="${KLAB_SCENARIO_MIPS_VERSIONS:-}";; mipsel) v="${KLAB_SCENARIO_MIPSEL_VERSIONS:-}";; esac; printf '%s\n' "${v:-$VERSIONS_DEFAULT}"; }
for arch in $ARCHES; do
  for v in $(versions_for_arch "$arch"); do
    target="upstream:$v"; case_done "$arch" "$target" && { echo "SKIP completed scenario: $target [$arch]"; continue; }
    safe="${v//[^A-Za-z0-9._-]/_}"; generated="$RUN_ROOT/generated/${arch}-${safe}.json"; report="$REPORT_ROOT/${arch}-${safe}"; log="$RUN_ROOT/${arch}-${safe}.log"
    "$SELF_DIR/lib/scenario_retarget.py" "$TEMPLATE" "$generated" "$target" "$arch"
    echo "===== scenario $target [$arch] =====" | tee "$log"
    set +e
    if [[ "$arch" == mips || "$arch" == mipsel ]]; then
      timeout --signal=TERM --kill-after=30 "$TIMEOUT" env KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 KLAB_ENABLE_EXPERIMENTAL_E2E=1 "$KLAB" scenario-run "$generated" --report-dir "$report" >>"$log" 2>&1
    else
      timeout --signal=TERM --kill-after=30 "$TIMEOUT" "$KLAB" scenario-run "$generated" --report-dir "$report" >>"$log" 2>&1
    fi
    rc=$?; set -e
    if (( rc==0 )); then status=PASS; elif (( rc==124 || rc==137 )); then status=TIMEOUT; else status=FAIL; fi
    record "$arch" "$target" "$rc" "$status" "$report"
  done
done
{
  echo "KLab coordinated scenario matrix: $RUN_ID"
  echo "Architectures: $ARCHES"
  echo "Versions default: $VERSIONS_DEFAULT"
  echo "Scenario: $TEMPLATE"
  echo "MIPS endian lanes enabled: $ENABLE_MIPS"
  echo; echo "Status counts:"; awk -F '\t' 'NR>1{c[$4]++}END{for(k in c)print "  " k,c[k]}' "$SUMMARY" | sort
  echo; echo "Failures/timeouts:"; awk -F '\t' 'NR>1&&$4!="PASS"{print "  "$1,$2,$4,"rc="$3,$5}' "$SUMMARY"
} > "$RUN_ROOT/REVIEW-ME.txt"
(
  cd "$KLAB_ROOT/results" || exit 1
  { find "logs/scenario-matrix/$RUN_ID" -type f -print; find "scenario-matrix/$RUN_ID" -type f ! -name '*.klab' -print; } | tar -czf "$RESULT_TAR" -T - 2>/dev/null || true
)
printf 'Results: %s\n' "$RESULT_TAR"
exit 0
