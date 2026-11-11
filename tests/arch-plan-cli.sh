#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" KLAB_ROOT="$T/klab" KLAB_ARCH_PROFILES_DIR="$ROOT/architectures"
mkdir -p "$HOME"
out="$(KLAB_BUILD_ARCH_OVERRIDE=x86_64 "$ROOT/kernel-lab.sh" arch-plan aarch64 --build x86_64 --kernel v6.6 --json)"
python3 - "$out" <<'PY'
import json,sys
m=json.loads(sys.argv[1]); assert m['target_arch']=='aarch64' and m['build_arch']=='x86_64' and m['cross_compile'] is True
PY
if KLAB_BUILD_ARCH_OVERRIDE=x86_64 "$ROOT/kernel-lab.sh" arch-plan aarch64 --kernel v3.6 >/dev/null 2>&1; then
  echo 'FAIL: arch-plan accepted Linux 3.6 for aarch64' >&2; exit 1
fi
grep -q '^mipsel' <("$ROOT/kernel-lab.sh" architectures) || { echo 'FAIL: mipsel profile not listed' >&2; exit 1; }
echo 'PASS: arch-plan CLI and version gating'
