#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq 'cleanup_internal_test_sessions' "$ROOT/klab-image-validate.sh"
grep -Fq '(fbld|ftst)-' "$ROOT/klab-image-validate.sh"
grep -Fq 'kill -0 "$pid"' "$ROOT/klab-image-validate.sh"
echo 'validation cleanup removes only stopped internal test sessions: PASS'
