#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -q 'host-tool-owners.tsv' "$ROOT/lib/buildenv-capture.sh"
grep -q 'dpkg-query -S' "$ROOT/lib/buildenv-capture.sh"
grep -q 'rpm -qf' "$ROOT/lib/buildenv-capture.sh"
grep -q 'host-tool ownership inventory missing' "$ROOT/klab-buildenv.sh"
grep -q 'recorded host-tool path missing' "$ROOT/klab-buildenv.sh"
echo 'distro-native host-tool ownership regression: PASS'
