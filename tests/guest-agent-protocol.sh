#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cc="${CC:-gcc}"
"$cc" -std=c11 -O2 -Wall -Wextra -Werror "$ROOT/guest-agent/klab-agent.c" -o "$T/agent"
grep -A2 '^int main' "$ROOT/guest-agent/klab-agent.c" | grep -Fq 'signal(SIGPIPE, SIG_IGN);' || { echo 'FAIL: guest-agent startup does not ignore SIGPIPE before forking' >&2; exit 1; }
grep -Fq 'for (int i = 0; i < 1000; i++)' "$ROOT/guest-agent/klab-agent.c" || { echo 'FAIL: guest-agent daemon readiness window is too short for emulated targets' >&2; exit 1; }
grep -Fq 'write_all(s, "PING\n", 5)' "$ROOT/guest-agent/klab-agent.c" || { echo 'FAIL: guest-agent readiness probe does not complete a request/response handshake' >&2; exit 1; }
grep -Fq 'if (g_stop) break; if (errno != EINTR) sleep_ms(10); continue;' "$ROOT/guest-agent/klab-agent.c" || { echo 'FAIL: guest-agent exits on recoverable accept errors' >&2; exit 1; }
grep -Fq '#define MAX_LINE 16384' "$ROOT/guest-agent/klab-agent.c" || { echo 'FAIL: guest-agent request buffer exceeds portable 32-bit guest limits' >&2; exit 1; }
sock="$T/agent.sock"; state="$T/state"
"$T/agent" --socket "$sock" --state "$state" start
trap '"$T/agent" --socket "$sock" --state "$state" shutdown >/dev/null 2>&1 || true; rm -rf "$T"' EXIT
"$T/agent" --socket "$sock" --state "$state" ping | grep -q '^OK PONG 1$'
for id in p1 p2 p3; do
  payload="$(python3 - "$T/agent" "$state" "$id" <<'PY'
import base64,sys
agent,state,pid=sys.argv[1:]
cmd=f"{agent} --state {state} barrier-run64 start 3 {pid} 15000 " + base64.b64encode(f"echo {pid}-done".encode()).decode()
print(base64.b64encode(cmd.encode()).decode())
PY
)"
  "$T/agent" --socket "$sock" --state "$state" spawn64 "$id" "$payload" >/dev/null
done
for id in p1 p2 p3; do
  "$T/agent" --socket "$sock" --state "$state" wait "$id" 17000 | grep -q "OK WAIT $id exited .* 0 0"
  [[ "$("$T/agent" --socket "$sock" --state "$state" output "$id" stdout)" == "$id-done" ]]
done
"$T/agent" --socket "$sock" --state "$state" event coordinated yes
"$T/agent" --socket "$sock" --state "$state" events | grep -q $'\tcoordinated\tyes$'
# process-group signaling
sleep64="$(python3 - <<'PY'
import base64
print(base64.b64encode(b'sleep 30').decode())
PY
)"
"$T/agent" --socket "$sock" --state "$state" spawn64 sleeper "$sleep64" >/dev/null
"$T/agent" --socket "$sock" --state "$state" signal sleeper 15 >/dev/null
"$T/agent" --socket "$sock" --state "$state" wait sleeper 5000 | grep -Eq '^OK WAIT sleeper exited .* 0 15$'
echo 'PASS: guest agent process/barrier/event protocol'

grep -Fq '#define MAX_REPLY 512' "$ROOT/guest-agent/klab-agent.c"
grep -Fq 'size_t cap = decode_data ? MAX_LINE : MAX_REPLY;' "$ROOT/guest-agent/klab-agent.c"
grep -Fq 'static char line[MAX_LINE];' "$ROOT/guest-agent/klab-agent.c"
grep -Fq "request[request_len++] = '\\n';" "$ROOT/guest-agent/klab-agent.c"
[[ "$(grep -c 'write_all(s, request, request_len)' "$ROOT/guest-agent/klab-agent.c")" == 1 ]]
