#!/usr/bin/env bash
# Focused first-live MIPS little-endian / Malta E2E matrix.
set -euo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export KLAB_MULTIARCH_ARCHES=mipsel
export KLAB_MULTIARCH_ENABLE_MIPS=1
export KLAB_MIPSEL_E2E_VERSIONS="${KLAB_MIPSEL_E2E_VERSIONS:-v4.14 v5.4 v5.15 v6.1 v6.6 v6.12 v7.0}"
exec "$SELF_DIR/klab-multiarch-overnight-r13.sh" "$@"
