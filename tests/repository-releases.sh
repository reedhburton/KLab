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
python3 "$ROOT/tools/klab-repo-release.py" squash "$T/source" update-1 complete
python3 "$ROOT/tools/klab-repo-release.py" export "$T/source" complete -o "$T/complete.tar.zst"
mkdir "$T/standalone"
python3 "$ROOT/tools/klab-repo-release.py" apply "$T/standalone" "$T/complete.tar.zst"
cmp "$T/source/a.klab" "$T/standalone/a.klab"
cmp "$T/source/b.klab" "$T/standalone/b.klab"
cmp "$T/source/sub/dependency.klabbuildenv" "$T/standalone/sub/dependency.klabbuildenv"
python3 - "$T/source/.klab-releases/snapshots/complete.json" <<'PY2'
import json,sys
doc=json.load(open(sys.argv[1]))
assert doc['parent'] is None
assert not doc['delta']['removed']
assert len(doc['delta']['changed']) == len(doc['files']) == 3
PY2
echo 'versioned repository base/delta/standalone releases: PASS'
