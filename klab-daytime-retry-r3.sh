#!/usr/bin/env bash
# Focused retry for defects found in the 2026-09-25 daytime sweep.
# Reuses successful caches/artifacts and reruns only Fedora plus cross-distro
# sections that had a known code/queue defect.
set -Eeuo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB_ROOT="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"
export KLAB_ROOT KLAB_HOME="$KLAB_ROOT"

export KLAB_DAY_UBUNTU=0
export KLAB_DAY_FEDORA=1
export KLAB_DAY_CROSS_DISTRO=1
export KLAB_DAY_FORCE_FEDORA_FALLBACK="${KLAB_DAY_FORCE_FEDORA_FALLBACK:-29,44}"
export KLAB_DAY_CROSS_SECTIONS="${KLAB_DAY_CROSS_SECTIONS:-debian,centos,oracle,amazon,opensuse,rocky,alpine}"
export KLAB_DAY_LOG_DIR="${KLAB_DAY_LOG_DIR:-$KLAB_ROOT/results/logs/daytime-retry-r3}"
export KLAB_DAY_ARTIFACT_DIR="${KLAB_DAY_ARTIFACT_DIR:-$KLAB_ROOT/transfer/exports/daytime-retry-r3}"

# The first Alpine run staged kernels with linux-headers rather than the
# kernel-specific external-module development trees. Force only those two
# stale captures to be rebuilt; other external distro roots remain reusable.
export KLAB_CROSS_RECAPTURE="${KLAB_CROSS_RECAPTURE:-alpine-linux-lts,alpine-linux-virt}"

printf '%s\n' \
  'KLab focused daytime retry r3' \
  "  root:           $KLAB_ROOT" \
  "  Fedora forced: $KLAB_DAY_FORCE_FEDORA_FALLBACK" \
  "  cross sections:$KLAB_DAY_CROSS_SECTIONS" \
  "  recapture:      $KLAB_CROSS_RECAPTURE"

exec "$SELF_DIR/klab-daytime-sweep-v1.sh"
