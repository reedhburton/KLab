#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
die(){ echo "FAIL: $*" >&2; exit 1; }
# Source minimal stubs + provider to inspect generated setup without Docker/network.
SELF_DIR="$ROOT"
release_snapshot_parts(){ RELEASE_BASE="${1%%@*}"; if [[ "$1" == *@* ]]; then RELEASE_SNAPSHOT="${1#*@}"; else RELEASE_SNAPSHOT=""; fi; }
source "$ROOT/lib/provider-core.sh"
source "$ROOT/providers/ubuntu.sh"
setup="$(klab_provider_ubuntu_setup 17.04)"
grep -Fq "suite='zesty'" <<<"$setup" || die '17.04 did not map to zesty'
grep -Fq 'mkdir -p /etc/apt/sources.list.d /var/lib/apt/lists/partial /var/cache/apt/archives/partial' <<<"$setup" || die 'historical APT setup does not recreate missing directories'
grep -Fq 'old-releases.ubuntu.com/ubuntu/' <<<"$setup" || die 'historical APT setup does not use old-releases'
# Verify the shell fragment itself can create sources.list from a deliberately empty
# fake root by translating absolute APT paths into a temporary root and stubbing apt-get.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat >"$tmp/bin/apt-get" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$tmp/bin/apt-get"
translated="$(printf '%s\n' "$setup" | sed "s#/etc/apt#$tmp/etc/apt#g; s#/var/lib/apt#$tmp/var/lib/apt#g; s#/var/cache/apt#$tmp/var/cache/apt#g")"
PATH="$tmp/bin:$PATH" bash -c "$translated"
[[ -f "$tmp/etc/apt/sources.list" ]] || die 'sources.list was not created from missing APT directory tree'
grep -Fq 'zesty main restricted universe multiverse' "$tmp/etc/apt/sources.list" || die 'generated sources.list is wrong'
echo 'PASS: Ubuntu historical APT setup recreates missing directory skeleton and writes zesty sources'
