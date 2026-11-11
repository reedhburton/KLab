#!/usr/bin/env bash
# Next-cycle feature umbrella: r14 architecture/process matrix + r15 multi-guest networking.
set -uo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}" KLAB_HOME="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"
rc=0
"$SELF_DIR/klab-feature-overnight-r14.sh" || rc=1
"$SELF_DIR/klab-multiguest-overnight-r15.sh" || rc=1
exit "$rc"
