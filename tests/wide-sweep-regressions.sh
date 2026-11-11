#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
die(){ echo "wide-sweep-regressions: ERROR: $*" >&2; exit 1; }

grep -Fq -- '--artifact-dir)' "$ROOT/kernel-lab.sh" || die '--artifact-dir parser regression remains'
grep -Fq 'KLAB_BUILDENV_REQUIRED_GCC_VERSION' "$ROOT/kernel-lab.sh" || die 'required GCC version is not propagated into buildenv capture'
grep -Fq 'buildenv-smoke-module-compilation-failed-rc=' "$ROOT/lib/buildenv-capture.sh" || die 'buildenv smoke still hides make failure'
grep -Fq 'olddefconfig is unavailable or failed' "$ROOT/kernel-lab.sh" || die 'legacy oldconfig fallback missing'
grep -Fq 'network/remote failure while fetching kernel tag' "$ROOT/kernel-lab.sh" || die 'git transport failures still collapse into tag-not-found'
grep -Fq 'printf '\''%s__%s'\'' "$TARGET" "$ARCH"' "$ROOT/matrix/run-one.sh" || die 'matrix key is not architecture-qualified'
grep -Fq 'Candidate:' "$ROOT/lib/backends/apt.sh" || die 'APT candidate validation missing'
grep -Fq 'Modules and modules-extra are optional split packages' "$ROOT/lib/backends/apt.sh" || die 'modules-extra is still treated as mandatory'
grep -Fq 'KLAB_BUILDENV_NATIVE_CC' "$ROOT/lib/backends/apt.sh" || die 'APT buildenv does not bind versioned GCC'
grep -Fq 'python3 >/dev/null' "$ROOT/lib/backends/rpm.sh" || die 'DNF toolchain path does not ensure python3'

echo 'wide-sweep-regressions: PASS'
