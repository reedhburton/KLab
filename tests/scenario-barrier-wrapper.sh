#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
source "$ROOT/lib/test-scenario.sh"
T="$(mktemp -d)"; trap 'rm -f /tmp/klab-agent; rm -rf "$T"' EXIT
gcc -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/guest-agent/klab-agent.c" -o "$T/agent"
ln -sf "$T/agent" /tmp/klab-agent
sock="$T/a.sock"; state=/tmp/klab-agent-state; rm -rf "$state"
"$T/agent" --socket "$sock" --state "$state" start
trap '"$T/agent" --socket "$sock" --state "$state" shutdown >/dev/null 2>&1 || true; rm -f /tmp/klab-agent; rm -rf "$state" "$T"' EXIT
for id in a b; do
  wrapped="$(klab_scenario_wrap_command "echo $id-ok" "$id" go 2 15000)"
  enc="$(klab_scenario_b64enc "$wrapped")"
  "$T/agent" --socket "$sock" --state "$state" spawn64 "$id" "$enc" >/dev/null
done
for id in a b; do
  "$T/agent" --socket "$sock" --state "$state" wait "$id" 17000 | grep -q "OK WAIT $id exited .* 0 0"
  [[ "$("$T/agent" --socket "$sock" --state "$state" output "$id" stdout)" == "$id-ok" ]]
done
echo 'PASS: scenario barrier command wrapper'
