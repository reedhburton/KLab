#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/source/sub" "$T/dest"; printf one >"$T/source/a.klab"; printf shared >"$T/source/sub/dependency.klabbuildenv"
python3 "$ROOT/tools/klab-repo-release.py" snapshot "$T/source" base
python3 "$ROOT/tools/klab-repo-release.py" export "$T/source" base -o "$T/base.tar.zst"
python3 "$ROOT/tools/klab-repo-release.py" apply "$T/dest" "$T/base.tar.zst"
cmp "$T/source/a.klab" "$T/dest/a.klab"; cmp "$T/source/sub/dependency.klabbuildenv" "$T/dest/sub/dependency.klabbuildenv"
printf two >"$T/source/b.klab"; printf changed >"$T/source/a.klab"
python3 "$ROOT/tools/klab-repo-release.py" snapshot "$T/source" update-1 --parent base
python3 "$ROOT/tools/klab-repo-release.py" export "$T/source" update-1 -o "$T/update-1.tar.zst"
python3 "$ROOT/tools/klab-repo-release.py" apply "$T/dest" "$T/update-1.tar.zst"
cmp "$T/source/a.klab" "$T/dest/a.klab"; cmp "$T/source/b.klab" "$T/dest/b.klab"
python3 "$ROOT/tools/klab-repo-release.py" apply "$T/dest" "$T/update-1.tar.zst"
python3 "$ROOT/tools/klab-repo-release.py" list "$T/source" | grep -q $'update-1\tbase'
mkdir "$T/wrong"; if python3 "$ROOT/tools/klab-repo-release.py" apply "$T/wrong" "$T/update-1.tar.zst" >/dev/null 2>&1; then echo 'delta accepted without parent' >&2; exit 1; fi
echo 'versioned repository base/delta releases: PASS'
