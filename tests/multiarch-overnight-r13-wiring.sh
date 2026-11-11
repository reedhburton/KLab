#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
S="$ROOT/klab-multiarch-overnight-r13.sh"
[[ -x "$S" ]] || { echo 'FAIL: r13 runner missing' >&2; exit 1; }
grep -q 'KLAB_MULTIARCH_ENABLE_MIPS' "$S"
grep -q 'KLAB_MIPSEL_E2E_VERSIONS' "$S"
grep -q 'KLAB_ENABLE_EXPERIMENTAL_ARCHES=1' "$S"
grep -q 'KLAB_ENABLE_EXPERIMENTAL_E2E=1' "$S"
[[ -x "$ROOT/klab-mipsel-overnight-r13.sh" ]] || { echo 'FAIL: focused mipsel runner missing' >&2; exit 1; }
echo 'PASS: r13 multiarch runner wiring'
