#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TARGET="ubuntu:17.04:4.10.0-42-generic"
ARCH=x86_64
BASE="${KLAB_LIVE_BASE:-${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}/work/live-tests/ubuntu1704}"
STAGE="$BASE/staging-home"; OFFLINE="$BASE/offline-home"; XFER="$BASE/transfer"; LOG="$BASE/live-validation.log"
mkdir -p "$BASE" "$XFER"; : >"$LOG"
exec > >(tee -a "$LOG") 2>&1
step(){ printf '\n===== %s =====\n' "$*"; }
trap 'rc=$?; echo "LIVE VALIDATION FAILED rc=$rc at line $LINENO"; echo "Log: $LOG"; exit $rc' ERR
step 'R29 network-free regression suite'
"$ROOT/tests/run-all.sh"
step 'staging doctor'
KLAB_ROOT="$STAGE" KLAB_HOME="$STAGE" "$ROOT/kernel-lab.sh" init --staging
KLAB_ROOT="$STAGE" KLAB_HOME="$STAGE" "$ROOT/kernel-lab.sh" doctor
step 'prepare exact Ubuntu 17.04 target with distro-native toolchain'
KLAB_ROOT="$STAGE" KLAB_HOME="$STAGE" "$ROOT/kernel-lab.sh" prepare "$TARGET" --arch "$ARCH" --distro-toolchain -o "$XFER/ubuntu-17.04-4.10.0-42-generic.klab"
step 'verify transfer artifacts'
for f in "$XFER"/*.klabdistrotoolchain; do [ -e "$f" ] || continue; "$ROOT/klab-distro-toolchain.sh" verify "$f"; done
for f in "$XFER"/*.klabbuildenv; do [ -e "$f" ] || continue; "$ROOT/klab-buildenv.sh" verify "$f"; done
"$ROOT/kernel-lab.sh" verify "$XFER/ubuntu-17.04-4.10.0-42-generic.klab"
step 'fresh offline import'
rm -rf "$OFFLINE"
KLAB_ROOT="$OFFLINE" KLAB_HOME="$OFFLINE" "$ROOT/kernel-lab.sh" init --offline
KLAB_ROOT="$OFFLINE" KLAB_HOME="$OFFLINE" "$ROOT/kernel-lab.sh" import "$XFER"
KLAB_ROOT="$OFFLINE" KLAB_HOME="$OFFLINE" "$ROOT/kernel-lab.sh" targets
step 'offline build + QEMU smoke/load test'
KLAB_ROOT="$OFFLINE" KLAB_HOME="$OFFLINE" "$ROOT/kernel-lab.sh" smoke "$TARGET" --arch "$ARCH"
step 'PASS'
echo "R29 LIVE PASS: $TARGET"
echo "Artifacts: $XFER"
echo "Log: $LOG"
