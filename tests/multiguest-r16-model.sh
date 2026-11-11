#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; P="$ROOT/lib/multiguest_plan.py"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
for f in two-lan-router-r16 link-flap-recovery-r16 process-failure-r16 guest-power-cut-r16 kernel-panic-r16; do "$P" validate "$ROOT/examples/multiguest/$f.json" >/dev/null; done
# Routed topology has two LANs, four NICs, forwarding router, and explicit routes.
[[ "$("$P" networks "$ROOT/examples/multiguest/two-lan-router-r16.json" | wc -l)" -eq 2 ]]
[[ "$("$P" interfaces "$ROOT/examples/multiguest/two-lan-router-r16.json" | wc -l)" -eq 4 ]]
"$P" guests "$ROOT/examples/multiguest/two-lan-router-r16.json" | grep -q $'router\tupstream:v6.6\tx86_64.*\t1$'
# Readiness dependency is normalized and orders server before client.
"$P" dependencies "$ROOT/examples/multiguest/two-lan-router-r16.json" | grep -q $'client\tclient\tserver\tserver\tready'
# The link recovery fault is edge-triggered at client start so the retrying client
# experiences the outage instead of starting only after the link is restored.
python3 - "$ROOT/examples/multiguest/link-flap-recovery-r16.json" <<'PY3'
import json,sys
x=json.load(open(sys.argv[1])); a=x['actions'][0]['after']
assert a == {'guest':'client','process':'client','state':'started'}, a
PY3
python3 - "$ROOT/examples/multiguest/two-lan-router-r16.json" "$T/cycle.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); x['guests'][0]['processes'][0]['depends_on']=[{'guest':'client','process':'client','state':'started'}]; x['guests'][2]['processes'][0]['depends_on']=[{'guest':'server','process':'server','state':'started'}]
json.dump(x,open(sys.argv[2],'w'))
PY
if "$P" validate "$T/cycle.json" >/dev/null 2>&1; then echo 'dependency cycle accepted' >&2; exit 1; fi

# Route gateways must be directly reachable, and link delay/fault durations cannot be negative.
python3 - "$ROOT/examples/multiguest/two-lan-router-r16.json" "$T/bad-route.json" <<'PY2'
import json,sys
x=json.load(open(sys.argv[1])); x['guests'][0]['routes'][0]['via']='10.99.99.1'; json.dump(x,open(sys.argv[2],'w'))
PY2
if "$P" validate "$T/bad-route.json" >/dev/null 2>&1; then echo 'unreachable route gateway accepted' >&2; exit 1; fi
python3 - "$ROOT/examples/multiguest/link-flap-recovery-r16.json" "$T/bad-delay.json" <<'PY2'
import json,sys
x=json.load(open(sys.argv[1])); x['networks'][0]['delay_us']=-1; json.dump(x,open(sys.argv[2],'w'))
PY2
if "$P" validate "$T/bad-delay.json" >/dev/null 2>&1; then echo 'negative network delay accepted' >&2; exit 1; fi
python3 - "$ROOT/examples/multiguest/link-flap-recovery-r16.json" "$T/bad-flap.json" <<'PY2'
import json,sys
x=json.load(open(sys.argv[1])); x['actions'][0]['down_ms']=-1; json.dump(x,open(sys.argv[2],'w'))
PY2
if "$P" validate "$T/bad-flap.json" >/dev/null 2>&1; then echo 'negative link flap accepted' >&2; exit 1; fi

# Destructive/signal action validation is fail-closed.
python3 - "$ROOT/examples/multiguest/process-failure-r16.json" "$T/bad-signal.json" <<'PY2'
import json,sys
x=json.load(open(sys.argv[1])); x['actions'][0]['signal']=0; json.dump(x,open(sys.argv[2],'w'))
PY2
if "$P" validate "$T/bad-signal.json" >/dev/null 2>&1; then echo 'signal 0 accepted' >&2; exit 1; fi
python3 - "$ROOT/examples/multiguest/process-failure-r16.json" "$T/bad-signal-high.json" <<'PY2'
import json,sys
x=json.load(open(sys.argv[1])); x['actions'][0]['signal']=65; json.dump(x,open(sys.argv[2],'w'))
PY2
if "$P" validate "$T/bad-signal-high.json" >/dev/null 2>&1; then echo 'signal 65 accepted' >&2; exit 1; fi
python3 - "$ROOT/examples/multiguest/guest-power-cut-r16.json" "$T/bad-expected.json" <<'PY2'
import json,sys
x=json.load(open(sys.argv[1])); x['actions'][0]['expected']='yes'; json.dump(x,open(sys.argv[2],'w'))
PY2
if "$P" validate "$T/bad-expected.json" >/dev/null 2>&1; then echo 'non-boolean destructive expected accepted' >&2; exit 1; fi

# Ready-triggered actions are active readiness consumers and therefore cannot drift
# until the later generic action phase. Destructive guest loss has explicit evidence.
grep -q 'klab_mg_has_pending_action_for_state.*ready' "$ROOT/lib/multiguest-scenario.sh" || grep -q 'pending_action_for_state "$k" ready' "$ROOT/lib/multiguest-scenario.sh"
grep -q 'guest-loss-results.tsv' "$ROOT/lib/multiguest-scenario.sh"
grep -q 'klab_mg_panic_since' "$ROOT/lib/multiguest-scenario.sh"
grep -q 'host pid .* not running before cut' "$ROOT/lib/multiguest-scenario.sh"

# Panic injection must be reproducible rather than depend on a distro/defconfig default.
grep -q 'MAGIC_SYSRQ' "$ROOT/kernel-lab.sh"


# Dependency failure policy is explicit and validated.
python3 - "$ROOT/examples/multiguest/two-lan-router-r16.json" "$T/dep-policy.json" <<'PY2'
import json,sys
x=json.load(open(sys.argv[1])); x['guests'][2]['processes'][0]['on_dependency_failure']='run'; json.dump(x,open(sys.argv[2],'w'))
PY2
"$P" processes "$T/dep-policy.json" | awk -F'\t' '$1=="client"&&$2=="client"{exit !($11=="run")} END{if(NR==0)exit 1}'
python3 - "$ROOT/examples/multiguest/two-lan-router-r16.json" "$T/bad-dep-policy.json" <<'PY2'
import json,sys
x=json.load(open(sys.argv[1])); x['guests'][2]['processes'][0]['on_dependency_failure']='explode'; json.dump(x,open(sys.argv[2],'w'))
PY2
if "$P" validate "$T/bad-dep-policy.json" >/dev/null 2>&1; then echo 'invalid dependency failure policy accepted' >&2; exit 1; fi

# Network filters and multi-link session plumbing must be present.
grep -q 'filter-dump' "$ROOT/kernel-lab.sh"
grep -q 'filter-buffer' "$ROOT/kernel-lab.sh"
grep -q -- '--net-link' "$ROOT/kernel-lab.sh"
grep -q 'qmp_set_link' "$ROOT/kernel-lab.sh"
echo PASS
