#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TARGET="${1:?target required}"
OUT="${KLAB_MATRIX_OUT:?set KLAB_MATRIX_OUT}"
ARCH="${KLAB_MATRIX_ARCH:-x86_64}"
KEY="$(printf '%s__%s' "$TARGET" "$ARCH" | tr '@/:' '____')"
BASE="$OUT/runs/$KEY"
[[ ! -e "$BASE" ]] || { echo "matrix run already exists: $BASE" >&2; exit 73; }
STAGE="$BASE/staging"; OFFLINE="$BASE/offline"; XFER="$BASE/transfer"; LOG="$BASE/run.log"; STATUS="$BASE/status.tsv"
mkdir -p "$XFER"; : >"$LOG"; printf 'started\t%s\n' "$TARGET" >"$STATUS"
exec > >(tee -a "$LOG") 2>&1
phase=init
trap 'rc=$?; printf "failed\t%s\trc=%s\n" "$phase" "$rc" >"$STATUS"; echo "MATRIX FAILED target=$TARGET phase=$phase rc=$rc"; exit $rc' ERR
phase=staging-init
KLAB_ROOT="$STAGE" KLAB_HOME="$STAGE" KLAB_COMPAT_LINKS=0 "$ROOT/kernel-lab.sh" init --staging
phase=prepare
artifact="$XFER/$KEY.klab"
KLAB_ROOT="$STAGE" KLAB_HOME="$STAGE" KLAB_COMPAT_LINKS=0 "$ROOT/kernel-lab.sh" prepare "$TARGET" --arch "$ARCH" --distro-toolchain -o "$artifact"
phase=verify
for f in "$XFER"/*.klabdistrotoolchain; do [[ ! -e "$f" ]] || "$ROOT/klab-distro-toolchain.sh" verify "$f"; done
for f in "$XFER"/*.klabbuildenv; do [[ ! -e "$f" ]] || "$ROOT/klab-buildenv.sh" verify "$f" --deep; done
"$ROOT/kernel-lab.sh" verify "$artifact"
phase=offline-init
KLAB_ROOT="$OFFLINE" KLAB_HOME="$OFFLINE" KLAB_COMPAT_LINKS=0 "$ROOT/kernel-lab.sh" init --offline
phase=offline-import
KLAB_ROOT="$OFFLINE" KLAB_HOME="$OFFLINE" KLAB_COMPAT_LINKS=0 "$ROOT/kernel-lab.sh" import "$XFER"
phase=smoke
KLAB_ROOT="$OFFLINE" KLAB_HOME="$OFFLINE" KLAB_COMPAT_LINKS=0 "$ROOT/kernel-lab.sh" smoke "$TARGET" --arch "$ARCH"
printf 'pass\tsmoke\t%s\n' "$TARGET" >"$STATUS"
echo "MATRIX PASS target=$TARGET"
