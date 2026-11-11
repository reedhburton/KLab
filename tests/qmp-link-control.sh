#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'kill ${srv:-} 2>/dev/null || true; rm -rf "$T"' EXIT
export KLAB_ROOT="$T/lab"
mkdir -p "$KLAB_ROOT/work/sessions/fake"
CTRL="$T/control.sock"; QMP="$T/qmp.sock"; LOG="$T/qmp.log"
python3 - "$CTRL" "$QMP" "$LOG" <<'PY' &
import json,os,socket,sys,threading
ctrl,qmp,log=sys.argv[1:]
for p in (ctrl,qmp):
 try: os.unlink(p)
 except FileNotFoundError: pass
cs=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); cs.bind(ctrl); cs.listen(4)
qs=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); qs.bind(qmp); qs.listen(4)
def hold():
 while True:
  try:c,_=cs.accept(); c.close()
  except:break
threading.Thread(target=hold,daemon=True).start()
# qmp_execute_json opens a fresh QMP connection per command.  Accept two so the
# test proves a complete down/up flap rather than only a one-way transition.
for _ in range(2):
 c,_=qs.accept(); f=c.makefile('rwb',buffering=0)
 f.write(b'{"QMP":{"version":{"qemu":{"major":9,"minor":0,"micro":0},"package":""},"capabilities":[]}}\n')
 while True:
  line=f.readline()
  if not line:break
  x=json.loads(line)
  with open(log,'a') as o:o.write(json.dumps(x,sort_keys=True)+'\n')
  if x.get('execute')=='qmp_capabilities':f.write(b'{"return":{}}\n')
  elif x.get('execute')=='set_link':f.write(b'{"return":{}}\n'); break
 c.close()
qs.close(); cs.close()
PY
srv=$!
for _ in {1..100}; do [[ -S "$CTRL" && -S "$QMP" ]] && break; sleep .02; done
cat > "$KLAB_ROOT/work/sessions/fake/session.env" <<EOF2
SESSION_BACKEND=linux
SESSION_ARCH=x86_64
SESSION_CONTROL='$CTRL'
SESSION_QMP='$QMP'
EOF2
printf '%s\n' "$$" > "$KLAB_ROOT/work/sessions/fake/pid"
out1="$($ROOT/kernel-lab.sh link fake klabnic1 down)"
out2="$($ROOT/kernel-lab.sh link fake klabnic1 up)"
[[ "$out1" == $'klabnic1\tdown' ]]
[[ "$out2" == $'klabnic1\tup' ]]
wait "$srv"
[[ "$(grep -c '"execute": "set_link"' "$LOG")" -eq 2 ]]
grep -q '"name": "klabnic1"' "$LOG"
grep -q '"up": false' "$LOG"
grep -q '"up": true' "$LOG"
echo PASS
# Panicked QEMU may ignore TERM; session stop must guarantee final cleanup.
grep -Fq 'kill -KILL "$pid"' "$ROOT/kernel-lab.sh"
