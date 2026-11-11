#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/lib/test-scenario.sh"
grep -Fq '"$margs64" "$munload" "$mname" >> "$report/module-map.tsv"' "$f" || { echo 'FAIL: encoded module args not preserved in map' >&2; exit 1; }
[[ "$(grep -Fc 'margs="$(klab_scenario_b64dec "$margs64")"' "$f")" -eq 3 ]] || { echo 'FAIL: module args not decoded at load and unload' >&2; exit 1; }
echo 'PASS: empty module arguments preserve internal map columns through load and unload'
