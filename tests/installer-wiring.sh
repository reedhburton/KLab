#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/install-m2.sh"
bash -n "$f"
grep -Fq 'apply-toolchain-boundary.py" "$tmp/klab-bundle.sh" "$tmp/kernel-lab.sh"' "$f"
grep -Fq 'KLAB_TOOLCHAIN_RUNTIME_BOUNDARY_M2' "$f"
grep -Fq 'KLAB_TOOLCHAIN_BOUNDARY_M2' "$f"
# Toolchain hardening must happen after the other mutations so it sees their
# final function shapes and the installed pair is verified as one boundary.
python3 - "$f" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
order=[
 'apply-provider-refactor.py',
 'apply-buildenv-refactor.py',
 'apply-buildenv-transfer.py',
 'apply-buildenv-import.py',
 'apply-atomic-target-import.py',
 'apply-toolchain-boundary.py',
]
pos=[s.index(x) for x in order]
assert pos == sorted(pos), (order,pos)
PY
grep -Fq 'TARGET [OFFLINE_ROOT] [ARCH]' "$ROOT/beta-tools/offline-smoke.sh"
grep -Fq 'KLAB_OFFLINE=1' "$ROOT/beta-tools/offline-smoke.sh"
grep -Fq -- '--arch "$arch"' "$ROOT/beta-tools/offline-smoke.sh"
grep -Fq 'tar -xzf "$sdkdest" -C "$sdkdir" --strip-components=1' "$ROOT/klab-bundle.sh"
grep -Fq 'chmod -R u+w "$path"' "$ROOT/klab-bundle.sh"
grep -Fq 'TARGET OUTPUT.klab [OFFLINE_ROOT] [ARCH]' "$ROOT/beta-tools/offline-repack-klab.sh"
grep -Fq 'KLAB_ARCH="$arch"' "$ROOT/beta-tools/offline-repack-klab.sh"
grep -Fq 'source "$bundle_dir/bundle.env"' "$ROOT/beta-tools/offline-repack-klab.sh"
grep -Fq 'Kernel image:' "$ROOT/beta-tools/offline-repack-klab.sh"
grep -Fq 'args+=(--include-sdk)' "$ROOT/beta-tools/offline-repack-klab.sh"
grep -Fq 'userspace=buildroot:minimal' "$ROOT/beta-tools/offline-repack-klab.sh"
grep -Fq 'artifacts/userspaces/busybox/$arch/busybox' "$ROOT/beta-tools/offline-repack-klab.sh"
grep -Fq -- '--include-toolchain "$BUNDLE_TOOLCHAIN_DIR"' "$ROOT/beta-tools/offline-repack-klab.sh"
echo 'installer-wiring: PASS'
