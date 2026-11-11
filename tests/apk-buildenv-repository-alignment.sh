#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
F="$ROOT/lib/backends/apk.sh"
grep -Fq 'apk upgrade --available --no-cache >/dev/null' "$F" || { echo 'FAIL: Alpine buildenv capture does not align the base image with the active repository before exact dependency capture' >&2; exit 1; }
grep -Fq 'exact installed APK origin version unavailable' "$F" || { echo 'FAIL: Alpine exact installed-version gate was weakened' >&2; exit 1; }
echo 'PASS: Alpine buildenv capture aligns installed packages before preserving the exact dependency closure'
