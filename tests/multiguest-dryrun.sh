#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export KLAB_ROOT="$T/lab"
out="$("$ROOT/kernel-lab.sh" multiguest-run "$ROOT/examples/multiguest/two-guest-network.json" --report-dir "$T/simple" --dry-run)"
grep -q $'^lan0\t10.77.0.0/24\t239\.192\.' <<<"$out"; grep -q $'^server\tupstream:v6.6\tx86_64' <<<"$out"; grep -q $'^client\tupstream:v6.6\tx86_64' <<<"$out"
python3 - "$T/simple/report.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x['schema']=='klab-multiguest-report-v2'; assert x['result']=='PASS'; assert len(x['guests'])==2; assert len(x['topology']['networks'])==1
PY
"$ROOT/kernel-lab.sh" multiguest-run "$ROOT/examples/multiguest/two-lan-router-r16.json" --report-dir "$T/router" --dry-run >/dev/null
python3 - "$T/router/report.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert len(x['guests'])==3; assert len(x['topology']['networks'])==2; assert {n['id'] for n in x['topology']['networks']}=={'lan-a','lan-b'}
PY
echo PASS
