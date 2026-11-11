#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export KLAB_ARCH_PROFILES_DIR="$ROOT/architectures"
SELF_DIR="$ROOT"
die(){ echo "provider-test: $*" >&2; exit 1; }
container_runtime(){ echo docker; }
run_container_root(){ :; }
source "$ROOT/lib/arch-model.sh"
source "$ROOT/lib/provider-core.sh"

klab_provider_fake_capabilities(){ echo 'list=yes fetch=yes build-module=yes buildenv=yes historical=yes snapshots=no cross-arch=no arches=x86_64,aarch64'; }
# Native/same-arch ARM worker should be accepted even though cross-arch=no.
KLAB_BUILD_ARCH_OVERRIDE=aarch64 klab_provider_assert_arch fake 1 aarch64
# x86 -> ARM staging must be rejected if provider doesn't advertise cross-arch.
if ( KLAB_BUILD_ARCH_OVERRIDE=x86_64; klab_provider_assert_arch fake 1 aarch64 ) >/dev/null 2>&1; then
  echo 'FAIL: cross-arch=no accepted x86->aarch64 staging' >&2; exit 1
fi
klab_provider_cross_capabilities(){ echo 'list=yes fetch=yes build-module=yes buildenv=yes historical=yes snapshots=no cross-arch=yes arches=x86_64,aarch64'; }
KLAB_BUILD_ARCH_OVERRIDE=x86_64 klab_provider_assert_arch cross 1 aarch64
if ( KLAB_BUILD_ARCH_OVERRIDE=x86_64; klab_provider_assert_arch fake 1 mipsel ) >/dev/null 2>&1; then
  echo 'FAIL: unsupported provider target arch accepted' >&2; exit 1
fi

echo 'PASS: provider target-arch vs staging-arch capability model'
