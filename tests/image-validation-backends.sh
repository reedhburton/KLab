#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; v="$ROOT/klab-image-validate.sh"
for token in 'backend=freebsd' 'bsd_conformance' 'bsd_ssh' 'klab-bsd-guest-conformance.sh' 'native:$provider:$release' 'buildroot:minimal' 'klab-buildroot-conformance.sh' 'ssh-keygen -q -t rsa'; do grep -Fq "$token" "$v"; done
grep -Fq "probe networking '" "$ROOT/klab-bsd-guest-conformance.sh"
grep -Fq 'passed" == 9' "$ROOT/klab-retained-bsd-conformance.sh"
echo 'image validation backend-specific standard/full gates: PASS'
grep -Fq 'freebsd:*:i386|freebsd:*:riscv64) backend=bsd-simple' "$v"

# Upstream full validation uses the minimal Buildroot root and injects the
# sealed Dropbear backend at session creation. It must not force a separate
# per-architecture buildroot:ssh image.
grep -Fq 'userspace=buildroot:minimal; conformance=' "$v"
! grep -Fq 'userspace=buildroot:ssh; conformance=' "$v"
