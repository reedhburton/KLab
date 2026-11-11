#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -q 'toolchain distro-capture' "$ROOT/kernel-lab.sh"
grep -q 'klab_provider_capture_toolchain' "$ROOT/lib/provider-core.sh"
grep -q 'klab_backend_apt_capture_toolchain' "$ROOT/lib/backends/apt.sh"
grep -q 'klab_backend_dnf_capture_toolchain' "$ROOT/lib/backends/rpm.sh"
grep -q 'klab_backend_yum_capture_toolchain' "$ROOT/lib/backends/rpm.sh"
for p in ubuntu debian fedora centos rhel; do grep -q "klab_provider_${p}_capture_toolchain" "$ROOT/providers/$p.sh"; done
grep -q '\*.klabdistrotoolchain' "$ROOT/kernel-lab.sh"
echo 'PASS: distro-native GCC/binutils artifact capture/import is wired across stable distro providers'
