#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -A3 '^session_rpc_exec()' "$ROOT/kernel-lab.sh" | grep -Fq 'python3 -S - "$socket" "$command" "$timeout_seconds"' || { echo 'FAIL: exec RPC does not skip unused Python site initialization' >&2; exit 1; }
echo 'session exec RPC fast Python startup: PASS'
