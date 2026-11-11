#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
S="$ROOT/klab-multiarch-overnight-r12.sh"
[[ -x "$S" ]] || { echo 'FAIL: r12 multiarch runner missing/not executable' >&2; exit 1; }
grep -q 'x86_64 i386 aarch64 armv7' "$S" || { echo 'FAIL: stable E2E arch set missing' >&2; exit 1; }
grep -q 'KLAB_MULTIARCH_RESUME_RUN_ID' "$S" || { echo 'FAIL: resume control missing' >&2; exit 1; }
grep -q 'QEMU_MISSING' "$S" || { echo 'FAIL: per-arch QEMU preflight missing' >&2; exit 1; }
grep -q 'KLAB_I386_E2E_VERSIONS' "$S" || { echo 'FAIL: i386 version override missing' >&2; exit 1; }
grep -q 'KLAB_ARMV7_E2E_VERSIONS' "$S" || { echo 'FAIL: armv7 version override missing' >&2; exit 1; }
grep -q 'EXPECTED_REJECT' "$S" || { echo 'FAIL: arm64 pre-3.7 capability check missing' >&2; exit 1; }
# Model profiles must declare E2E status explicitly.
for a in x86_64 i386 aarch64 armv7; do grep -q '^E2E_STATUS=stable$' "$ROOT/architectures/$a.conf" || { echo "FAIL: $a lacks stable E2E status" >&2; exit 1; }; done
for a in mips mipsel mips64 mips64el; do grep -q '^E2E_STATUS=experimental$' "$ROOT/architectures/$a.conf" || { echo "FAIL: $a lacks experimental E2E status" >&2; exit 1; }; done
echo 'PASS: r12 multiarch overnight wiring'
