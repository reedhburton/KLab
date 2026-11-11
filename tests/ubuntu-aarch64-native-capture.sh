#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
grep -Fq 'KLAB_PROVIDER_CONTAINER_PLATFORM="$platform" klab_backend_apt_capture_toolchain' "$ROOT/providers/ubuntu.sh"
grep -Fq 'KLAB_PROVIDER_CONTAINER_PLATFORM="$platform" klab_backend_apt_capture_buildenv' "$ROOT/providers/ubuntu.sh"
grep -Fq 'platform=linux/arm64' "$ROOT/providers/ubuntu.sh"
grep -Fq 'KLAB_UBUNTU_AARCH64_IMAGE:-arm64v8/ubuntu:' "$ROOT/providers/ubuntu.sh"
grep -Fq 'platform_args=(--platform "$KLAB_PROVIDER_CONTAINER_PLATFORM")' "$ROOT/lib/provider-core.sh"
echo 'PASS: Ubuntu aarch64 native toolchain and buildenv capture select an ARM64 provider container'
