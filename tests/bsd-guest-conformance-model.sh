#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; bash -n "$ROOT/klab-bsd-guest-conformance.sh" "$ROOT/klab-retained-bsd-conformance.sh"
for c in identity filesystem kernel_interfaces processes toolchain runtime networking modules shutdown_path; do grep -Fq "probe $c " "$ROOT/klab-bsd-guest-conformance.sh"; done
grep -Fq 'qemu10-aarch64-container' "$ROOT/klab-retained-bsd-conformance.sh"; grep -Fq 'kernel-lab.sh" smoke' "$ROOT/klab-retained-bsd-conformance.sh"; grep -Fq 'passed" == 9' "$ROOT/klab-retained-bsd-conformance.sh"
echo 'BSD guest conformance model: PASS'
