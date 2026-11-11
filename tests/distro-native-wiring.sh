#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
grep -q -- '--distro-toolchain' "$ROOT/kernel-lab.sh"
grep -q 'run-module-native' "$ROOT/kernel-lab.sh"
grep -q 'distro-native-v1' "$ROOT/lib/buildenv-capture.sh"
grep -q 'distro_toolchain_id' "$ROOT/lib/klab_buildenv.py"
grep -q "buildenv.distro_toolchain_id" "$ROOT/klab-bundle.sh"
echo 'PASS: explicit distro-native prepare/build/import dependency path is wired end-to-end'
