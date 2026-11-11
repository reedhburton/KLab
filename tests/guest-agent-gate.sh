#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap '"$T/agent" --socket "$T/agent.sock" --state "$T/state" shutdown >/dev/null 2>&1 || true; rm -rf "$T"' EXIT
cc -Wall -Wextra -Werror -O2 -std=c11 "$ROOT/guest-agent/klab-agent.c" -o "$T/agent"
"$T/agent" --socket "$T/agent.sock" --state "$T/state" start
one="$(printf 'echo one-ok' | base64 -w0)"; two="$(printf 'echo two-ok' | base64 -w0)"
"$T/agent" --state "$T/state" gate-run64 launch g1 5000 "$one" > "$T/one" & p1=$!
"$T/agent" --state "$T/state" gate-run64 launch g2 5000 "$two" > "$T/two" & p2=$!
for _ in $(seq 1 100); do
  s1="$("$T/agent" --state "$T/state" gate-status launch g1)"; s2="$("$T/agent" --state "$T/state" gate-status launch g2)"
  [[ "$s1" == WAITING && "$s2" == WAITING ]] && break
  sleep .02
done
[[ "$s1" == WAITING && "$s2" == WAITING ]]
"$T/agent" --state "$T/state" gate-release launch
wait "$p1"; wait "$p2"
grep -qx one-ok "$T/one"; grep -qx two-ok "$T/two"
[[ "$("$T/agent" --state "$T/state" gate-status launch g1)" == RELEASED ]]
echo PASS
