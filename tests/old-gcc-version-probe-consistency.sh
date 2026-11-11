#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Every distro-toolchain capture path must prefer -dumpfullversion and fall back
# to -dumpversion; the runtime re-proof must use the same contract.
for f in "$ROOT/lib/backends/apt.sh" "$ROOT/lib/backends/rpm.sh"; do
  grep -q -- '-dumpfullversion' "$f"
  grep -q -- '-dumpversion' "$f"
done
# rpm.sh has both dnf and yum capture implementations; prevent the legacy yum
# path from regressing to a dumpversion-only probe.
python3 - "$ROOT/lib/backends/rpm.sh" <<'PY'
import sys
s=open(sys.argv[1]).read()
start=s.index('klab_backend_yum_capture_toolchain()')
chunk=s[start:]
assert "-dumpfullversion" in chunk and "-dumpversion" in chunk
PY
grep -q -- '--version | head -n1 | grep -oE' "$ROOT/klab-buildenv.sh"
grep -q 'def ccver(tool):' "$ROOT/lib/backends/apt.sh"
echo PASS
