#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq 'module_param(value, int, 0644)' "$ROOT/tests/all-five/module/klab_coord.c"
grep -Fq 'exec /bin/sh -c' "$ROOT/tests/all-five/workload.sh"
grep -Fq 'KLAB_ALL_FIVE_MODULE_PROCESS_PASS' "$ROOT/tests/all-five/workload.sh"
bash -n "$ROOT/tests/all-five/workload.sh"
echo 'PASS: all-five module/process workload has stable cross-version interfaces'
