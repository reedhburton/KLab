#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
f="$ROOT/kernel-lab.sh"
grep -Fq 'session_rpc_exec "$sock" '\''sync; poweroff -f 2>/dev/null || reboot -f 2>/dev/null || true'\'' 1 >/dev/null 2>&1 || true' "$f" || {
  echo 'FAIL: session stop does not bound the expected disconnecting poweroff RPC' >&2
  exit 1
}
echo 'bounded session-stop poweroff RPC: PASS'
