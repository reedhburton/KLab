#!/usr/bin/env bash
# Next-cycle r14 feature overnight: multi-arch E2E + big/little MIPS + coordinated process scenarios.
set -euo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"
export KLAB_MULTIARCH_ENABLE_MIPS="${KLAB_MULTIARCH_ENABLE_MIPS:-1}"
export KLAB_SCENARIO_ENABLE_MIPS="${KLAB_SCENARIO_ENABLE_MIPS:-1}"
"$SELF_DIR/klab-multiarch-overnight-r14.sh"
"$SELF_DIR/klab-scenario-overnight-r14.sh"
