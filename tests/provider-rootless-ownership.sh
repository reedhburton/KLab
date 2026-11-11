#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
grep -Fq 'owner="$(klab_provider_bind_output_owner)"' "$ROOT/kernel-lab.sh" || { echo "FAIL: RPM extraction bypasses rootless-aware bind ownership" >&2; exit 1; }
die(){ echo "provider-rootless-ownership: ERROR: $*" >&2; exit 1; }
SELF_DIR="$ROOT"
KLAB_PROVIDER_ROOT="$ROOT/providers"
KLAB_PROVIDER_BACKEND_ROOT="$ROOT/lib/backends"
run_container_root(){ :; }
source "$ROOT/lib/provider-core.sh"

KLAB_CONTAINER_ROOTLESS=1
[[ "$(klab_provider_bind_output_owner)" == 0:0 ]] ||
  die "rootless container output owner must be container uid/gid 0:0"
[[ "$(klab_backend_host_owner)" == 0:0 ]] ||
  die "APT backend did not use rootless-aware owner"
[[ "$(klab_backend_rpm_host_owner)" == 0:0 ]] ||
  die "RPM backend did not use rootless-aware owner"

KLAB_CONTAINER_ROOTLESS=0
expected="${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}"
[[ "$(klab_provider_bind_output_owner)" == "$expected" ]] ||
  die "rootful owner mismatch"
[[ "$(klab_backend_host_owner)" == "$expected" ]] ||
  die "APT backend rootful owner mismatch"
[[ "$(klab_backend_rpm_host_owner)" == "$expected" ]] ||
  die "RPM backend rootful owner mismatch"

echo "provider-rootless-ownership: PASS"
