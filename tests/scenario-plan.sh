#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
S="$ROOT/examples/scenarios/multiprocess-basic.json"
python3 "$ROOT/lib/scenario_plan.py" validate "$S" >/dev/null
meta="$(python3 "$ROOT/lib/scenario_plan.py" meta "$S")"
grep -q '^upstream:v6.6$' <<<"$meta"
grep -q '^x86_64$' <<<"$meta"
[[ "$(python3 "$ROOT/lib/scenario_plan.py" builds "$S" | wc -l)" -eq 1 ]]
[[ "$(python3 "$ROOT/lib/scenario_plan.py" processes "$S" | wc -l)" -eq 3 ]]
[[ "$(python3 "$ROOT/lib/scenario_plan.py" modules "$S" | wc -l)" -eq 1 ]]
python3 "$ROOT/lib/scenario_plan.py" processes "$S" | awk -F '\t' '{if($5!="start"||$6!=3) exit 1}'
echo 'PASS: scenario schema/planner'
