#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'kill ${cpid:-} ${spid:-} 2>/dev/null || true; rm -rf "$T"' EXIT
export KLAB_ROOT="$T/lab"

# 1. The routed topology must survive the real multiguest runner's validation,
# planning and report-finalization path even when no QEMU is available.
"$ROOT/kernel-lab.sh" multiguest-run "$ROOT/examples/multiguest/two-lan-router-r16.json" --report-dir "$T/router" --dry-run >/dev/null
python3 - "$T/router/report.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
assert x['result']=='PASS'
assert len(x['topology']['networks'])==2
assert len(x['topology']['interfaces'])==4
router=next(g for g in x['scenario']['guests'] if g['id']=='router')
assert router['forward_ipv4'] is True
assert len(router['interfaces'])==2
server=next(g for g in x['scenario']['guests'] if g['id']=='server')
client=next(g for g in x['scenario']['guests'] if g['id']=='client')
assert server['routes']==[{'to':'10.77.20.0/24','via':'10.77.10.1'}]
assert client['routes']==[{'to':'10.77.10.0/24','via':'10.77.20.1'}]
PY

# 2. The fault scenario must preserve capture + delay metadata and be edge-triggered
# from the client start event.  That makes the retrying client live during the outage.
"$ROOT/kernel-lab.sh" multiguest-run "$ROOT/examples/multiguest/link-flap-recovery-r16.json" --report-dir "$T/flap" --dry-run >/dev/null
python3 - "$T/flap/report.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); s=x['scenario']; a=s['actions'][0]
assert a['type']=='link-flap'
assert a['after']=={'guest':'client','process':'client','state':'started'}
assert a['down_ms']==800
assert any(n['capture'] for n in s['networks'])
assert next(n for n in s['networks'] if n['id']=='lan-b')['delay_us']==5000
PY

# 3. Prove the runner contains the edge hooks in all three observable states.
grep -q 'klab_mg_fire_actions_for_state "$k" started' "$ROOT/lib/multiguest-scenario.sh"
grep -q 'klab_mg_fire_actions_for_state "$k" ready' "$ROOT/lib/multiguest-scenario.sh"
grep -q 'klab_mg_fire_actions_for_state "$k" exited' "$ROOT/lib/multiguest-scenario.sh"

# 4. Exercise a complete QMP down/up sequence against a synthetic QMP server.
"$ROOT/tests/qmp-link-control.sh" >/dev/null

# 5. Exercise the userspace retry behavior used by the link recovery scenario:
# start the client while no server is reachable, then make the endpoint available.
gcc -O2 -std=c11 -Wall -Wextra -Werror "$ROOT/examples/network-pair.c" -o "$T/network-pair"
port="$(python3 - <<'PY'
import socket
s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()
PY
)"
"$T/network-pair" client 127.0.0.1 "$port" recovered-after-flap >"$T/client.out" 2>"$T/client.err" & cpid=$!
sleep 0.8
"$T/network-pair" server "$port" 1 >"$T/server.out" 2>"$T/server.err" & spid=$!
wait "$cpid"; cpid=''
wait "$spid"; spid=''
grep -q 'CLIENT_RX ACK:recovered-after-flap' "$T/client.out"
grep -q 'SERVER_RX recovered-after-flap' "$T/server.out"

echo PASS
