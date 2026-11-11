#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
bash -n "$ROOT/klab-retained-conformance-queue.sh"
grep -Fq 'ubuntu|fedora|alpine|debian|centos' "$ROOT/klab-retained-conformance-queue.sh"
grep -Fq 'native:$provider:$release' "$ROOT/klab-retained-conformance-queue.sh"
grep -Fq 'klab-guest-conformance.sh' "$ROOT/klab-retained-conformance-queue.sh"
grep -Fq 'passed" == 9' "$ROOT/klab-retained-conformance-queue.sh"
grep -Fq "awk -F '\\t'" "$ROOT/klab-retained-conformance-queue.sh"
grep -Fq 'sha256sum | cut -c1-12' "$ROOT/klab-retained-conformance-queue.sh"
grep -Fq 'session_root=' "$ROOT/klab-retained-conformance-queue.sh"
grep -Fq 'KLAB_CONFORMANCE_BOOT_ATTEMPTS:-3' "$ROOT/klab-retained-conformance-queue.sh"
grep -Fq 'boot attempt %s/%s' "$ROOT/klab-retained-conformance-queue.sh"
echo 'retained conformance queue: PASS'
