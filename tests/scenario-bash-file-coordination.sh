#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T" /tmp/klab-demo' EXIT
scenario="$ROOT/examples/scenarios/bash-file-coordination.json"
python3 "$ROOT/lib/scenario_plan.py" validate "$scenario" > "$T/normalized.json"
python3 - "$T/normalized.json" "$T" <<'PY'
import json,subprocess,sys,time,os
x=json.load(open(sys.argv[1])); out=sys.argv[2]
cmd={p['id']:p['command'] for p in x['processes']}
reader=subprocess.Popen(['/bin/sh','-c',cmd['bash_session']],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
producer=subprocess.Popen(['/bin/sh','-c',cmd['file_producer']],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
pout,perr=producer.communicate(timeout=15); rout,rerr=reader.communicate(timeout=15)
open(out+'/reader.out','w').write(rout);open(out+'/producer.out','w').write(pout)
assert producer.returncode==0,(producer.returncode,perr)
assert reader.returncode==0,(reader.returncode,rerr)
assert 'BASHPID=' in rout
assert 'READ_ONE=hello-from-producer' in rout
assert 'READ_TWO=producer-observed-ack' in rout
assert 'BASH_SESSION_DONE' in rout
PY
grep -q '^ack:hello-from-producer$' /tmp/klab-demo/ack
echo 'PASS: persistent Bash reader and ordered file producer coordinate correctly'
