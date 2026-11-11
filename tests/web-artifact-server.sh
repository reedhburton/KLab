#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; pid=''
trap '[[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; rm -rf "$T"' EXIT
mkdir -p "$T/root/targets/kernels/ubuntu/24.04/x86_64/6.8-test" "$T/root/work/sessions/dev" "$T/root/results/tests/run1" "$T/repo/nested"
cat >"$T/root/targets/kernels/ubuntu/24.04/x86_64/6.8-test/bundle.env" <<'EOF'
BUNDLE_KERNEL_RELEASE=6.8-test
BUNDLE_ARCH=x86_64
BUNDLE_GUEST_USERSPACE_SPEC=buildroot:minimal
EOF
cat >"$T/root/work/sessions/dev/session.env" <<'EOF'
SESSION_TARGET=ubuntu:24.04:6.8-test
SESSION_ARCH=x86_64
SESSION_BACKEND=linux
SESSION_USERSPACE=buildroot:minimal
EOF
printf '999999999\n' >"$T/root/work/sessions/dev/pid"
printf 'target\tresult\trc\nx@x86_64\tPASS\t0\n' >"$T/root/results/tests/run1/status.tsv"
printf 'artifact-data' >"$T/repo/nested/test.klab"
printf 'secret-token\n' >"$T/token"
python3 "$ROOT/tools/klab-serve.py" --root "$T/root" --repo "$T/repo" --port 0 --port-file "$T/port" --upload-token-file "$T/token" >"$T/server.log" 2>&1 &
pid=$!
for _ in $(seq 1 100); do [[ -s "$T/port" ]] && break; sleep .05; done
[[ -s "$T/port" ]] || { cat "$T/server.log"; exit 1; }
port="$(cat "$T/port")"
python3 - "$port" "$T" <<'PY'
import hashlib,json,sys,urllib.error,urllib.request
port,tmp=sys.argv[1:]
base='http://127.0.0.1:'+port
assert urllib.request.urlopen(base+'/healthz').read()==b'ok\n'
status=json.load(urllib.request.urlopen(base+'/api/status'))
assert status['targets'][0]['target']=='ubuntu:24.04:6.8-test'
assert status['jobs']['sessions'][0]['state']=='stopped'
assert status['jobs']['queues'][0]['counts']['PASS']==1
assert status['artifacts'][0]['file']=='nested/test.klab'
req=urllib.request.Request(base+'/repo/nested/test.klab',headers={'Range':'bytes=0-7'})
with urllib.request.urlopen(req) as r:
 assert r.status==206 and r.read()==b'artifact' and r.headers['Accept-Ranges']=='bytes'
try: urllib.request.urlopen(base+'/repo/../token')
except urllib.error.HTTPError as e: assert e.code==404
else: raise AssertionError('traversal accepted')
payload=b'uploaded-klab'
req=urllib.request.Request(base+'/api/artifacts/incoming/new.klab',data=payload,method='PUT',
 headers={'Authorization':'Bearer secret-token','X-KLab-SHA256':hashlib.sha256(payload).hexdigest()})
with urllib.request.urlopen(req) as r: assert r.status==201
assert open(tmp+'/repo/incoming/new.klab','rb').read()==payload
bad=urllib.request.Request(base+'/api/artifacts/no.klab',data=b'x',method='PUT')
try: urllib.request.urlopen(bad)
except urllib.error.HTTPError as e: assert e.code==401
else: raise AssertionError('unauthorized upload accepted')
assert b'KLab dashboard' in urllib.request.urlopen(base+'/').read()
PY
echo 'klab web dashboard and artifact repository: PASS'
