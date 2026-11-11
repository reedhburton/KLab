#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
file="$ROOT/lib/arch-e2e.sh"
grep -Fq 'klab_arch_e2e_read_rpc()' "$file" || { echo 'FAIL: read-only RPC retry helper missing' >&2; exit 1; }
grep -Fq "klab_arch_e2e_read_rpc \"\$SESSION_CONTROL\" 'dmesg' \"\$KLAB_ARCH_SMOKE_REPORT_DIR/module-unload-dmesg.txt\"" "$file" || { echo 'FAIL: unload evidence is not using retry-safe RPC' >&2; exit 1; }
grep -Fq 'cmd_unload_module_session "$KLAB_ARCH_SMOKE_SESSION" hello' "$file" || { echo 'FAIL: state-changing unload command missing' >&2; exit 1; }
if grep -Fq "klab_arch_e2e_read_rpc \"\$SESSION_CONTROL\" 'rmmod" "$file"; then echo 'FAIL: state-changing RPC must not be retried' >&2; exit 1; fi
echo 'PASS: architecture E2E retries read-only serial evidence without replaying state changes'
