#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OUT="${1:-${KLAB_ALTERNATE_OUT:-$HOME/klab-data/results/popular-alternate-kernels}}"
MANIFEST="${KLAB_ALTERNATE_MANIFEST:-$SELF/matrix/popular-alternate-kernels.tsv}"
mkdir -p "$OUT/ubuntu-debian" "$OUT/arch"

# Ubuntu and Debian provider targets receive normal KLab full validation. The
# manifest intentionally retains only representative recent flavour revisions.
"$SELF/klab-distro-expansion-queue.sh" "$MANIFEST" "$OUT/ubuntu-debian"

# Arch is rolling and currently enters through the external/custom acquisition
# path. Preserve each exact resolved uname/header pair, then require the normal
# validation matrix before promotion to the supported-target catalog.
KLAB_CROSS_SECTIONS=arch \
KLAB_CROSS_EXPORT_DIR="$OUT/arch/exports" \
KLAB_CROSS_STAGE_DIR="$OUT/arch/staged" \
KLAB_CROSS_LOG_DIR="$OUT/arch/logs" \
"$SELF/klab-cross-distro-queue-r4.sh"
