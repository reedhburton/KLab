#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/lib/backends/rpm.sh"
grep -Fq 'dnf -q repoquery --location "$spec"' "$F" || { echo 'installed-NEVRA repo location fallback missing' >&2; exit 1; }
grep -Fq 'if [ -f "/pkgs/$expected_file" ]' "$F" || { echo 'captured target RPM fast path missing' >&2; exit 1; }
grep -Fq 'elif [ -f "/klab-distro-toolchain-packages/$expected_file" ]' "$F" || { echo 'captured distro-toolchain RPM fast path missing' >&2; exit 1; }
grep -Fq 'elif [ -f "/klab-buildenv-aux-repo/$expected_file" ]' "$F" || { echo 'mounted exact-repo fast path missing' >&2; exit 1; }
grep -Fq 'file://*) cp "${location#file://}" "$out/packages/"' "$F" || { echo 'local exact-repo copy fallback missing' >&2; exit 1; }
grep -Fq 'http://*|https://*) curl -fsSL "$location"' "$F" || { echo 'remote exact-repo download fallback missing' >&2; exit 1; }
grep -Fq 'downloaded RPM identity mismatch' "$F" || { echo 'download fallback is not protected by exact RPM identity verification' >&2; exit 1; }
echo 'PASS: RPM closure capture resolves installed exact NEVRAs through repository locations with identity verification'
