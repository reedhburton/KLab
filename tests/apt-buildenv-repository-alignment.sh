#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
F="$ROOT/lib/backends/apt.sh"
grep -Fq 'apt-get dist-upgrade -y -qq' "$F" || { echo 'FAIL: APT buildenv capture does not align the base image with authenticated repository candidates' >&2; exit 1; }
grep -Fq 'exact installed dependency archive unavailable' "$F" || { echo 'FAIL: exact installed dependency gate was weakened' >&2; exit 1; }
grep -Fq 'for source_dir in /pkgs /klab-distro-toolchain-packages' "$F" || { echo 'FAIL: exact mounted archive recovery missing' >&2; exit 1; }
grep -Fq 'dpkg-deb -f "$candidate" Version' "$F" || { echo 'FAIL: recovered archive version is not verified' >&2; exit 1; }
echo 'PASS: APT buildenv capture aligns installed packages before preserving the exact closure'
