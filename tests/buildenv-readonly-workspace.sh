#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
grep -Fq 'chmod -R u+w "$tmp"' "$ROOT/lib/buildenv-capture.sh" || { echo "FAIL: read-only capture cleanup is not unlock-safe" >&2; exit 1; }
f="$ROOT/klab-buildenv.sh"
grep -Fq 'local tcbase=/tmp/klab-toolchain' "$f"
grep -Fq 'M=/tmp/klab-work/module' "$f"
grep -Fq -- '--tmpfs /tmp --dir /tmp/klab-work --dir /tmp/klab-work/module --dir "$tcbase"' "$f"
grep -Fq -- '--ro-bind "$tcroot" "$tcbase" --bind "$(readlink -f "$module")" /tmp/klab-work/module --chdir /tmp/klab-work/module' "$f"
! grep -Fq 'M=/work/module' "$f"
! grep -Fq '/opt/klab-toolchain' "$f"
echo 'buildenv read-only workspace regression: PASS'
