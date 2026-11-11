#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
KLAB_ROOT="$tmp/root" bash -c 'source "$1/lib/klab-root.sh"; klab_root_ensure_layout; test -f "$KLAB_STATE/.layout-v1"; rm -rf "$KLAB_WORK/jobs"; klab_root_ensure_layout; test ! -e "$KLAB_WORK/jobs"; rm -f "$KLAB_STATE/.layout-v1"; klab_root_ensure_layout; test -d "$KLAB_WORK/jobs"' _ "$ROOT"
echo 'unified-root layout marker fast path: PASS'
