#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/processes" "$T/builds" "$T/modules"
cat > "$T/scenario.normalized.json" <<'JSON'
{"schema":"klab-scenario-v1","target":"upstream:v6.6","arch":"x86_64","processes":[]}
JSON
cat > "$T/architecture-plan.json" <<'JSON'
{"schema":"klab-arch-plan-v1","target_arch":"x86_64"}
JSON
printf 'id\texpected_exit\tactual_exit\tsignal\twait_rc\tstatus\nworker1\t0\t0\t0\t0\tPASS\n' > "$T/process-results.tsv"
printf 'hello\n' > "$T/processes/worker1.stdout"; : > "$T/processes/worker1.stderr"
printf 'id\tname\tload_rc\tstatus\nhello\thello\t0\tPASS\n' > "$T/module-load-results.tsv"
printf 'id\tname\tunload_rc\tstatus\nhello\thello\t0\tPASS\n' > "$T/module-unload-results.tsv"
printf '1700000000000\t123\tready\tworker1\n' > "$T/events.tsv"
printf 'kernel log\n' > "$T/dmesg.txt"
printf 'binary\n' > "$T/builds/worker"
printf 'module\n' > "$T/modules/hello.ko"
# shellcheck disable=SC1090
source "$ROOT/lib/test-scenario.sh"
KLAB_SCENARIO_REPORT="$T" KLAB_SCENARIO_STAGE=complete KLAB_SCENARIO_SESSION='' KLAB_SCENARIO_KEEP_SESSION=1
klab_scenario_finalize 0
python3 - "$T/report.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
assert x['schema']=='klab-scenario-report-v1'
assert x['result']=='PASS'
assert x['processes'][0]['stdout_path']=='processes/worker1.stdout'
assert x['modules'][0]['load_status']=='PASS' and x['modules'][0]['unload_status']=='PASS'
assert x['events'][0]['name']=='ready'
assert x['architecture_plan']['target_arch']=='x86_64'
assert x['dmesg_path']=='dmesg.txt'
assert len(x['artifacts'])==2
PY
echo 'PASS: scenario canonical report'
