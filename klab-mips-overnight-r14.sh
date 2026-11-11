#!/usr/bin/env bash
# Focused r14 MIPS endian E2E matrix: big-endian mips + little-endian mipsel.
set -euo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export KLAB_ENABLE_EXPERIMENTAL_ARCHES=1
export KLAB_ENABLE_EXPERIMENTAL_E2E=1
export KLAB_MULTIARCH_ENABLE_MIPS=1
export KLAB_MULTIARCH_ARCHES="${KLAB_MIPS_ARCHES:-mips mipsel}"
export KLAB_MIPS_E2E_VERSIONS="${KLAB_MIPS_E2E_VERSIONS:-v4.14 v5.4 v5.15 v6.1 v6.6 v6.12 v7.0}"
export KLAB_MIPSEL_E2E_VERSIONS="${KLAB_MIPSEL_E2E_VERSIONS:-v4.14 v5.4 v5.15 v6.1 v6.6 v6.12 v7.0}"
exec "$SELF_DIR/klab-multiarch-overnight-r14.sh" "$@"
