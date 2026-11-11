#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
grep -Fq 'linux_karch_for_source "${BUNDLE_ARCH:-$ARCH}" "${BUNDLE_SOURCE_DIR:-$BUNDLE_BUILD_DIR}"' "$ROOT/kernel-lab.sh"
# Distro header bundles legitimately omit BUNDLE_SOURCE_DIR. Under nounset the
# exact fallback used by the production path must select their build tree.
unset BUNDLE_SOURCE_DIR
BUNDLE_BUILD_DIR=/target/root/usr/src/linux-headers-test
[[ "${BUNDLE_SOURCE_DIR:-$BUNDLE_BUILD_DIR}" == "$BUNDLE_BUILD_DIR" ]]
BUNDLE_SOURCE_DIR=/target/source
[[ "${BUNDLE_SOURCE_DIR:-$BUNDLE_BUILD_DIR}" == "$BUNDLE_SOURCE_DIR" ]]
echo 'offline-optional-source-dir: PASS'
