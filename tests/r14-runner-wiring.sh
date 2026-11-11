#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
grep -q 'ARCHES="$ARCHES mips"' "$ROOT/klab-multiarch-overnight-r14.sh"
grep -q 'ARCHES="$ARCHES mipsel"' "$ROOT/klab-multiarch-overnight-r14.sh"
grep -q 'mips) var=KLAB_MIPS_E2E_VERSIONS' "$ROOT/klab-multiarch-overnight-r14.sh"
grep -q 'scenario-run' "$ROOT/klab-scenario-overnight-r14.sh"
grep -q 'KLAB_SCENARIO_ENABLE_MIPS' "$ROOT/klab-scenario-overnight-r14.sh"
grep -q 'klab-multiarch-overnight-r14.sh' "$ROOT/klab-feature-overnight-r14.sh"
grep -q 'klab-scenario-overnight-r14.sh' "$ROOT/klab-feature-overnight-r14.sh"
echo 'PASS: r14 overnight runner wiring'
