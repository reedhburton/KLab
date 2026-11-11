#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
scenario="$ROOT/examples/scenarios/intentional-kernel-panic.json"
python3 "$ROOT/lib/scenario_plan.py" validate "$scenario" > "$T/normalized.json"
expect="$(python3 "$ROOT/lib/scenario_plan.py" panic-expectation "$scenario")"
IFS=$'\t' read -r module pattern64 timeout <<<"$expect"
[[ "$module" == intentional_panic && "$timeout" == 15000 ]]
pattern="$(python3 - "$pattern64" <<'PY'
import base64,sys
print(base64.b64decode(sys.argv[1]).decode())
PY
)"
[[ "$pattern" == 'KLab intentional panic validation' ]]
grep -Fq 'panic("KLab intentional panic validation")' "$ROOT/examples/panic-module/klab_intentional_panic.c"
grep -Fq 'crash_log_has_panic "$console_path" && grep -Fq -- "$panic_pattern"' "$ROOT/lib/test-scenario.sh"
grep -Fq 'capture_session_crash "$KLAB_SCENARIO_SESSION"' "$ROOT/lib/test-scenario.sh"
grep -Fq "EXPECTED_PANIC" "$ROOT/lib/test-scenario.sh"
echo 'PASS: intentional panic requires fresh generic and suite-specific console evidence'
