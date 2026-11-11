#!/usr/bin/env bash
# Package logs/metadata from an interrupted KLab overnight regression.
set -Eeuo pipefail
KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"
LOG_BASE="${KLAB_OVERNIGHT_LOG_DIR:-$KLAB_ROOT/results/logs/overnight-regression}"
RUN_ID="${1:-latest}"
if [[ "$RUN_ID" == latest ]]; then
  RUN_ID="$(find "$LOG_BASE" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | LC_ALL=C sort | tail -n1)"
fi
[[ -n "$RUN_ID" ]] || { echo "ERROR: no overnight run found under $LOG_BASE" >&2; exit 2; }
RUN_ROOT="$LOG_BASE/$RUN_ID"
[[ -d "$RUN_ROOT" ]] || { echo "ERROR: overnight run not found: $RUN_ROOT" >&2; exit 2; }
OUT="$KLAB_ROOT/results/overnight-regression-${RUN_ID}-partial-results.tar.gz"
mkdir -p "$KLAB_ROOT/results"
tar -C "$LOG_BASE" -czf "$OUT" "$RUN_ID"
echo "$OUT"
