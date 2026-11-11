#!/usr/bin/env bash
# Next-cycle feature umbrella: r15 multi-arch/multi-guest coverage + r16 topology/fault injection.
set -uo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}" KLAB_HOME="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"
rc=0
"$SELF_DIR/klab-feature-overnight-r15.sh" || rc=1
"$SELF_DIR/klab-fault-overnight-r16.sh" || rc=1
exit "$rc"
