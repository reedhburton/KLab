#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
python3 "$ROOT/lib/scenario_plan.py" validate "$ROOT/examples/scenarios/ordered-suite.json" > "$T/normalized.json"
python3 - "$T/normalized.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); owner=x['processes'][0]['command']; responder=x['processes'][1]['command']
assert 'KLAB_SEQUENCE_PID=$$' in owner
assert 'klab-sequence-events/module_ready' in owner
assert 'klab-sequence-events/responder_done' in owner
assert 'exec /bin/sh -c' in owner
assert 'klab-sequence-events/module_ready' in responder
assert x['modules'][0]['auto_load'] is False
PY
policies="$(python3 "$ROOT/lib/scenario_plan.py" module-policies "$ROOT/examples/scenarios/ordered-suite.json")"
[[ "$policies" == *$'\t0' ]] || { echo 'FAIL: manual module mode not emitted' >&2; exit 1; }
cat > "$T/bad.json" <<'JSON'
{"target":"upstream:v6.6","arch":"x86_64","processes":[{"id":"bad","steps":[{"exec":"true"},{"run":"false"}]}]}
JSON
! python3 "$ROOT/lib/scenario_plan.py" validate "$T/bad.json" >/dev/null 2>&1
echo 'PASS: ordered process steps and same-PID final exec plan'
