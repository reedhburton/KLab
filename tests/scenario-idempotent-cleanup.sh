#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/lib/test-scenario.sh"
grep -Fq '[[ -f "$dir/pid" ]] || return 0' "$f" || { echo 'FAIL: cleanup does not tolerate an absent session pid' >&2; exit 1; }
grep -Fq 'kill -0 "$pid" 2>/dev/null || return 0' "$f" || { echo 'FAIL: cleanup retries an already stopped session' >&2; exit 1; }
echo 'PASS: scenario finalization cleanup is idempotent after normal session stop'
