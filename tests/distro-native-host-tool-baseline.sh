#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# Static regression: native execution must explicitly preflight host-side kbuild
# utilities inside the sealed distro root.  This is not package provenance; it
# prevents accidental erosion of the runtime contract while reconstruction
# provenance is developed separately.
for t in '/bin/sh' '/usr/bin/make' awk sed grep find xargs basename dirname tr cut sort head mkdir rm cp mv ln cat; do
  grep -Fq "$t" "$ROOT/klab-buildenv.sh" || { echo "FAIL: missing native host-tool baseline entry $t" >&2; exit 1; }
done
grep -Fq 'distro-native host-tool baseline missing:' "$ROOT/klab-buildenv.sh"
grep -Fq 'unalias -a' "$ROOT/klab-buildenv.sh" || { echo 'FAIL: runtime baseline resolution is alias-sensitive' >&2; exit 1; }
grep -Fq 'unalias -a' "$ROOT/lib/buildenv-capture.sh" || { echo 'FAIL: capture baseline resolution is alias-sensitive' >&2; exit 1; }
grep -Fq 'exit 65' "$ROOT/klab-buildenv.sh"
for p in bash coreutils findutils gawk grep sed; do
  grep -Eq "(dnf|yum) -qy install .*\b${p}\b" "$ROOT/lib/backends/rpm.sh" || { echo "FAIL: RPM buildenv does not install baseline package $p" >&2; exit 1; }
done
echo 'PASS: distro-native runtime has an explicit conservative host-tool baseline preflight'
