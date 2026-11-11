#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
P="$ROOT/lib/multiguest_plan.py"
T="$(mktemp -d)"
agent_pid=''
cleanup(){
  if [[ -x "$T/agent" && -S "$T/agent.sock" ]]; then "$T/agent" --socket "$T/agent.sock" --state "$T/state" shutdown >/dev/null 2>&1 || true; fi
  [[ -n "$agent_pid" ]] && kill "$agent_pid" >/dev/null 2>&1 || true
  rm -rf "$T"
}
trap cleanup EXIT

# The three destructive/failure scenarios must normalize to the intended trigger semantics.
for f in process-failure-r16 guest-power-cut-r16 kernel-panic-r16; do
  "$P" validate "$ROOT/examples/multiguest/$f.json" > "$T/$f.normalized.json"
done
python3 - "$T/process-failure-r16.normalized.json" "$T/guest-power-cut-r16.normalized.json" "$T/kernel-panic-r16.normalized.json" <<'PY'
import json,sys
sig,power,panic=[json.load(open(p)) for p in sys.argv[1:]]
a=sig['actions'][0]
assert a['type']=='signal' and a['signal']==15
assert a['after']=={'guest':'worker','process':'victim','state':'ready'}
for x,typ in ((power,'guest-power-cut'),(panic,'kernel-panic')):
    a=x['actions'][0]
    assert a['type']==typ and a['expected'] is True
    assert a['after']['state']=='ready'
PY

# Exercise the signal path with the real static guest-agent implementation on the host.
cc="${CC:-gcc}"
"$cc" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/guest-agent/klab-agent.c" -o "$T/agent"
"$T/agent" --socket "$T/agent.sock" --state "$T/state" start
payload="$(python3 - <<'PY'
import base64
print(base64.b64encode(b'echo VICTIM_READY; sleep 30').decode())
PY
)"
"$T/agent" --socket "$T/agent.sock" --state "$T/state" spawn64 victim "$payload" >/dev/null
ready=0
for _ in {1..100}; do
  if "$T/agent" --socket "$T/agent.sock" --state "$T/state" output victim stdout 2>/dev/null | grep -q 'VICTIM_READY'; then ready=1; break; fi
  sleep .02
done
[[ "$ready" == 1 ]] || { echo 'victim never became ready' >&2; exit 1; }
"$T/agent" --socket "$T/agent.sock" --state "$T/state" signal victim 15 >/dev/null
"$T/agent" --socket "$T/agent.sock" --state "$T/state" wait victim 5000 | grep -Eq '^OK WAIT victim exited .* 0 15$'

# Panic evidence must be newer than the injection point. An old panic line is not enough.
console="$T/console.log"
printf 'boot\nKernel panic - old crash\nrebooted\n' > "$console"
before="$(wc -c < "$console")"
printf 'normal output after injection attempt\n' >> "$console"
if tail -c "+$((before+1))" "$console" | grep -Eqi 'Kernel panic|not syncing:|PANIC: double fault|(^|[[:space:]])panic:|Fatal trap [0-9]+'; then
  echo 'stale panic marker incorrectly accepted as fresh evidence' >&2; exit 1
fi
printf 'Kernel panic - not syncing: synthetic new crash\n' >> "$console"
tail -c "+$((before+1))" "$console" | grep -Eqi 'Kernel panic|not syncing:|PANIC: double fault|(^|[[:space:]])panic:|Fatal trap [0-9]+'

# Exercise the production helper under nounset; its offset must be initialized
# after the local `before` value is bound.
source "$ROOT/lib/multiguest-scenario.sh"
klab_mg_panic_since "$console" "$before"
if klab_mg_panic_since "$console" "$(wc -c < "$console")"; then
  echo 'production helper accepted no new panic bytes' >&2; exit 1
fi

# The runner must explicitly consume readiness for ready-triggered actions and record loss evidence.
grep -q 'klab_mg_has_pending_action_for_state "$k" ready' "$ROOT/lib/multiguest-scenario.sh"
grep -q 'guest-loss-results.tsv' "$ROOT/lib/multiguest-scenario.sh"
grep -q 'new panic marker missing after byte' "$ROOT/lib/multiguest-scenario.sh"
grep -Fq 'rm -f "$report/error-context.txt"' "$ROOT/lib/multiguest-scenario.sh"
grep -q 'not running before cut' "$ROOT/lib/multiguest-scenario.sh"

echo 'PASS: r16 destructive-fault synthetic validation'
