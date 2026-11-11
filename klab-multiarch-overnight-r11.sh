#!/usr/bin/env bash
# Feature validation matrix for the r11 cross-architecture E2E path.
# This is intended for the NEXT overnight cycle, not the currently-running r9 sweep.
set -uo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB="${KLAB_MULTIARCH_KLAB:-$SELF_DIR/kernel-lab.sh}"
KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"; export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"
ARCH="${KLAB_MULTIARCH_ARCH:-aarch64}"
USERSPACE="${KLAB_MULTIARCH_USERSPACE:-buildroot:minimal}"
VERSIONS="${KLAB_AARCH64_VERSIONS:-v4.14 v5.4 v5.15 v6.1 v6.6 v6.12 v7.0}"
TIMEOUT="${KLAB_MULTIARCH_CASE_TIMEOUT:-10800}"
RUN_ID="${KLAB_MULTIARCH_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_ROOT="$KLAB_ROOT/results/logs/multiarch-e2e/$RUN_ID"
REPORT_ROOT="$KLAB_ROOT/results/multiarch-e2e/$RUN_ID"
SUMMARY="$RUN_ROOT/summary.tsv"
RESULT_TAR="$KLAB_ROOT/results/multiarch-e2e-${RUN_ID}-results.tar.gz"
mkdir -p "$RUN_ROOT" "$REPORT_ROOT"
printf 'arch\ttarget\trc\tstatus\treport\n' > "$SUMMARY"

run_one(){
  local v="$1" target="upstream:$v" safe log report rc status
  safe="${v//[^A-Za-z0-9._-]/_}"; log="$RUN_ROOT/${ARCH}-${safe}.log"; report="$REPORT_ROOT/${ARCH}-${safe}"
  mkdir -p "$report"
  echo "===== $target [$ARCH] =====" | tee "$log"
  set +e
  timeout --signal=TERM --kill-after=30 "$TIMEOUT" \
    "$KLAB" arch-smoke "$target" --arch "$ARCH" --userspace "$USERSPACE" --artifact-dir "$report" \
    >>"$log" 2>&1
  rc=$?
  set -e
  if (( rc==0 )); then status=PASS; else status=FAIL; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$ARCH" "$target" "$rc" "$status" "$report" >> "$SUMMARY"
}

# Planning sanity: pre-arm64 kernel must be rejected.
set +e
"$KLAB" arch-smoke upstream:v3.6 --arch aarch64 --dry-run >"$RUN_ROOT/pre37.log" 2>&1
pre_rc=$?
set -e
printf 'aarch64\tupstream:v3.6\t%s\t%s\t%s\n' "$pre_rc" "$([[ $pre_rc -ne 0 ]] && echo EXPECTED_REJECT || echo REGRESSION)" "$RUN_ROOT/pre37.log" >> "$SUMMARY"

for v in $VERSIONS; do run_one "$v"; done
{
  echo "KLab multi-arch E2E run: $RUN_ID"
  echo "Architecture: $ARCH"
  echo "Userspace: $USERSPACE"
  echo "Versions: $VERSIONS"
  echo
  awk -F '\t' 'NR>1{c[$4]++} END{for(k in c) print k, c[k]}' "$SUMMARY" | sort
} > "$RUN_ROOT/REVIEW-ME.txt"
tar -czf "$RESULT_TAR" -C "$KLAB_ROOT/results" "logs/multiarch-e2e/$RUN_ID" "multiarch-e2e/$RUN_ID" 2>/dev/null || true
printf 'Results: %s\n' "$RESULT_TAR"
exit 0
