#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)";T="$(mktemp -d)";trap 'rm -rf "$T"' EXIT
mkdir -p "$T/root" "$T/archive";printf 'immutable artifact\n' >"$T/archive/example.klab"
export KLAB_ROOT="$T/root" KLAB_STAGE_FREE_GIB=0
python3 "$ROOT/tools/klab-stage.py" volume-add "$T/archive" >/dev/null
staged="$(python3 "$ROOT/tools/klab-stage.py" stage "$T/archive/example.klab")";[[ -f "$staged" ]];cmp "$T/archive/example.klab" "$staged"
[[ "$(python3 "$ROOT/tools/klab-stage.py" stage "$T/archive/example.klab")" == "$staged" ]]
python3 "$ROOT/tools/klab-stage.py" status 2>"$T/e"|grep -q example.klab;grep -q 'objects=1' "$T/e"
printf x >"$T/outside.klab";! python3 "$ROOT/tools/klab-stage.py" stage "$T/outside.klab" 2>/dev/null
rm "$T/archive/example.klab";[[ -f "$staged" ]];python3 "$ROOT/tools/klab-stage.py" prune --free-gib 0 >/dev/null
echo 'archive-staging: PASS'
