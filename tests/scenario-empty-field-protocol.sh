#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
cat > "$t/s.json" <<JSON
{"schema":"klab-scenario-v1","target":"upstream:v6.6","arch":"x86_64","modules":[{"id":"hello","source_dir":"$ROOT/examples/hello-module","args":"","unload_after":true,"name":"hello"}],"processes":[]}
JSON
line="$(python3 "$ROOT/lib/scenario_plan.py" modules "$t/s.json")"
IFS=$'\t' read -r id src args unload name <<<"$line"
[[ "$id" == hello && "$args" == __KLAB_EMPTY__ && "$unload" == 1 && "$name" == hello ]] || { echo "FAIL: empty field shifted planner columns: $line" >&2; exit 1; }
dec="$(python3 - "$args" <<'PY'
import base64,sys
v=sys.argv[1]; print('' if v=='__KLAB_EMPTY__' else base64.b64decode(v).decode())
PY
)"
[[ -z "$dec" ]]
echo 'PASS: empty scenario fields preserve TSV column positions'
