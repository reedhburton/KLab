#!/usr/bin/env python3
"""KLab FreeBSD serial guest-agent client for isolated QEMU tests."""
import argparse, base64, os, shlex, socket, time, uuid

def connect(path, timeout=10):
    s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); end=time.monotonic()+timeout
    while True:
        try: s.connect(path); return s
        except OSError:
            if time.monotonic()>=end: raise
            time.sleep(.1)

def execute(path, cmd, timeout=30):
    s=connect(path); s.settimeout(timeout); f=s.makefile('rwb',buffering=0); tok=uuid.uuid4().hex[:16]
    f.write(f"EXEC {tok} {base64.b64encode(cmd.encode()).decode()}\n".encode()); out=bytearray()
    while True:
        line=f.readline()
        if not line: raise RuntimeError('control channel closed before response')
        p=line.decode('ascii','replace').rstrip('\n').split(' ',2)
        if p[0]=='DATA' and len(p)==3 and p[1]==tok: out.extend(base64.b64decode(p[2]))
        elif p[0]=='END' and len(p)>=3 and p[1]==tok:
            rc=int(p[2]); s.close(); return rc,bytes(out)

def ready(path, timeout):
    deadline=time.monotonic()+timeout; s=connect(path,timeout); f=s.makefile('rwb',buffering=0)
    while True:
        remain=deadline-time.monotonic()
        if remain<=0: raise TimeoutError('guest did not announce readiness')
        s.settimeout(remain); line=f.readline()
        if not line: raise RuntimeError('control channel closed before readiness')
        if line.startswith(b'READY'): break
    s.close(); rc,out=execute(path,'uname -r',30)
    if rc: raise SystemExit(rc)
    print(out.decode(),end='')

def put(path, local, remote, mode):
    rc,out=execute(path,f"mkdir -p {shlex.quote(os.path.dirname(remote))}; : > {shlex.quote(remote)}; chmod {shlex.quote(mode)} {shlex.quote(remote)}")
    if rc: raise RuntimeError(out.decode(errors='replace'))
    with open(local,'rb') as f:
        while True:
            chunk=f.read(24)
            if not chunk: break
            data=base64.b64encode(chunk).decode()
            rc,out=execute(path,f"printf '%s' {shlex.quote(data)} | base64 -d >> {shlex.quote(remote)}")
            if rc: raise RuntimeError(out.decode(errors='replace'))
    rc,out=execute(path,f"wc -c < {shlex.quote(remote)}")
    actual=int(out.strip()); expected=os.path.getsize(local)
    if rc or actual!=expected: raise RuntimeError(f'upload size mismatch {actual} != {expected}')
    print(actual)

def main():
    p=argparse.ArgumentParser(); p.add_argument('--socket',required=True); sub=p.add_subparsers(dest='cmd',required=True)
    q=sub.add_parser('ready'); q.add_argument('--timeout',type=int,default=300)
    q=sub.add_parser('exec'); q.add_argument('--timeout',type=int,default=300); q.add_argument('command')
    q=sub.add_parser('put'); q.add_argument('local'); q.add_argument('remote'); q.add_argument('--mode',default='0644')
    a=p.parse_args()
    if a.cmd=='ready': ready(a.socket,a.timeout)
    elif a.cmd=='exec':
        rc,out=execute(a.socket,a.command,a.timeout); print(out.decode(errors='replace'),end=''); raise SystemExit(rc)
    else: put(a.socket,a.local,a.remote,a.mode)
if __name__=='__main__': main()
