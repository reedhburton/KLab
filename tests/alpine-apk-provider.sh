#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
die(){ echo "alpine-apk-provider: ERROR: $*" >&2; exit 1; }
ARCH=x86_64
source "$ROOT/lib/backends/apk.sh"
[[ "$(klab_backend_apk_arch x86_64)" == x86_64 ]] || die 'x86_64 mapping failed'
[[ "$(klab_backend_apk_arch amd64)" == x86_64 ]] || die 'amd64 mapping failed'
grep -Fq 'apk verify' "$ROOT/lib/backends/apk.sh" || die 'APK signature verification missing'
grep -Fq 'linux-lts linux-lts-dev' "$ROOT/lib/backends/apk.sh" || die 'kernel/header capture missing'
! grep -Fq 'apk fetch --recursive --output /out linux-lts linux-lts-dev' "$ROOT/lib/backends/apk.sh" || die 'kernel capture recursively includes firmware catalog'
grep -Fq "p.suffix in ('.deb','.rpm','.apk')" "$ROOT/lib/buildenv-capture.sh" || die 'buildenv manifest rejects APKs'
grep -Fq "alpine) printf 'alpine:%s" "$ROOT/kernel-lab.sh" || die 'Alpine image routing missing'
grep -Fq 'seen_paths[path]=owner' "$ROOT/lib/klab_buildenv.py" || die 'same-owner multicall executable support missing'
echo 'alpine-apk-provider: PASS'
