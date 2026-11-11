#!/usr/bin/env python3
import argparse, base64, json, os, re, shlex, sys
SAFE = re.compile(r'^[A-Za-z0-9._-]+$')

def b64(s):
    text = str(s)
    return base64.b64encode(text.encode()).decode() if text else '__KLAB_EMPTY__'
def step_command(process, default_timeout):
    """Compile ordered steps into one shell process; the final exec preserves its PID."""
    steps=process.get('steps')
    if steps is None:
        command=process.get('command')
        if not isinstance(command,str) or not command: raise SystemExit(f"process {process.get('id','')} missing command or steps")
        return command
    if not isinstance(steps,list) or not steps: raise SystemExit(f"process {process.get('id','')} steps must be a non-empty list")
    lines=['set -eu', 'KLAB_SEQUENCE_PID=$$', 'export KLAB_SEQUENCE_PID', 'mkdir -p /tmp/klab-sequence-events']
    for n,step in enumerate(steps,1):
        if not isinstance(step,dict): raise SystemExit(f"process {process.get('id','')} step {n} must be an object")
        wait=step.get('wait_for')
        if wait is not None:
            if not isinstance(wait,str) or not SAFE.match(wait): raise SystemExit(f"process {process.get('id','')} step {n} has invalid wait_for")
            timeout=int(step.get('timeout_seconds',process.get('timeout_seconds',default_timeout)))
            if timeout < 1: raise SystemExit(f"process {process.get('id','')} step {n} timeout must be positive")
            path=shlex.quote('/tmp/klab-sequence-events/'+wait)
            lines += [f'_klab_deadline=$(( $(date +%s) + {timeout} ))', f'while [ ! -e {path} ]; do [ "$(date +%s)" -lt "$_klab_deadline" ] || {{ echo "timeout waiting for {wait}" >&2; exit 124; }}; sleep 1; done']
        run=step.get('run'); final=step.get('exec')
        if run is not None and final is not None: raise SystemExit(f"process {process.get('id','')} step {n} cannot contain both run and exec")
        if run is not None:
            if not isinstance(run,str) or not run: raise SystemExit(f"process {process.get('id','')} step {n} has invalid run")
            lines.append(run)
        if final is not None:
            if not isinstance(final,str) or not final: raise SystemExit(f"process {process.get('id','')} step {n} has invalid exec")
            if n != len(steps): raise SystemExit(f"process {process.get('id','')} exec must be the final step")
            if step.get('signal') is not None: raise SystemExit(f"process {process.get('id','')} final exec cannot signal after replacement")
            lines.append('exec /bin/sh -c '+shlex.quote('exec '+final))
        signal=step.get('signal')
        if signal is not None:
            if not isinstance(signal,str) or not SAFE.match(signal): raise SystemExit(f"process {process.get('id','')} step {n} has invalid signal")
            path=shlex.quote('/tmp/klab-sequence-events/'+signal)
            lines += [f': > {path}', f'/tmp/klab-agent --state /tmp/klab-agent-state event sequence_signal {shlex.quote(signal)}']
        if wait is None and run is None and final is None and signal is None: raise SystemExit(f"process {process.get('id','')} step {n} is empty")
    return '\n'.join(lines)
def load(path):
    with open(path, 'r', encoding='utf-8') as f: obj=json.load(f)
    if obj.get('schema') not in (None,'klab-scenario-v1'):
        raise SystemExit('unsupported scenario schema')
    for k in ('target','arch'):
        if not isinstance(obj.get(k),str) or not obj[k]: raise SystemExit(f'missing scenario {k}')
    obj.setdefault('schema','klab-scenario-v1'); obj.setdefault('profile','normal'); obj.setdefault('userspace','buildroot:minimal'); obj.setdefault('timeout_seconds',60)
    obj.setdefault('builds',[]); obj.setdefault('files',[]); obj.setdefault('modules',[]); obj.setdefault('processes',[]); obj.setdefault('collect',{'dmesg':True,'events':True})
    panic=obj.get('expected_panic')
    if panic is not None:
        if not isinstance(panic,dict) or not SAFE.match(str(panic.get('module',''))): raise SystemExit('expected_panic requires a valid module id')
        if not isinstance(panic.get('pattern'),str) or not panic['pattern']: raise SystemExit('expected_panic requires a console pattern')
        panic.setdefault('timeout_seconds',15)
    ids=set()
    for p in obj['processes']:
        pid=p.get('id','')
        if not isinstance(pid,str) or not SAFE.match(pid): raise SystemExit(f'invalid process id: {pid!r}')
        if pid in ids: raise SystemExit(f'duplicate process id: {pid}')
        ids.add(pid)
        p.setdefault('timeout_seconds',obj['timeout_seconds']); p.setdefault('expected_exit',0)
        p['command']=step_command(p,obj['timeout_seconds'])
        if 'barrier' in p:
            br=p['barrier']
            if not isinstance(br,dict) or not SAFE.match(str(br.get('name',''))): raise SystemExit(f'process {pid} invalid barrier')
            if int(br.get('count',0)) < 1: raise SystemExit(f'process {pid} invalid barrier count')
            br.setdefault('timeout_seconds',p['timeout_seconds'])
    mids=set()
    for m in obj['modules']:
        mid=m.get('id','')
        if not isinstance(mid,str) or not SAFE.match(mid): raise SystemExit(f'invalid module id: {mid!r}')
        if mid in mids: raise SystemExit(f'duplicate module id: {mid}')
        mids.add(mid)
        if not isinstance(m.get('source_dir'),str) or not m['source_dir']: raise SystemExit(f'module {mid} missing source_dir')
        m.setdefault('args',''); m.setdefault('unload_after',True); m.setdefault('name',mid); m.setdefault('auto_load',True)
    bids=set()
    for x in obj['builds']:
        bid=x.get('id','')
        if not isinstance(bid,str) or not SAFE.match(bid): raise SystemExit(f'invalid build id: {bid!r}')
        if bid in bids: raise SystemExit(f'duplicate build id: {bid}')
        bids.add(bid)
        src=x.get('source')
        if not isinstance(src,str) or not src: raise SystemExit(f'build {bid} missing source')
        x.setdefault('remote',f'/tmp/{bid}'); x.setdefault('static',True); x.setdefault('flags',[])
    for x in obj['files']:
        if not isinstance(x.get('source'),str) or not isinstance(x.get('remote'),str) or not x['remote'].startswith('/'):
            raise SystemExit('scenario file entries require source and absolute remote path')
        x.setdefault('mode','0644')
    return obj

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('command',choices=['validate','meta','builds','files','modules','module-policies','panic-expectation','processes']); ap.add_argument('scenario'); a=ap.parse_args(); o=load(a.scenario)
    if a.command=='validate': json.dump(o,sys.stdout,indent=2,sort_keys=True); print(); return
    if a.command=='meta':
        print(o['target']); print(o['arch']); print(o['profile']); print(o['userspace']); print(int(o['timeout_seconds'])); return
    if a.command=='builds':
        for x in o['builds']: print('\t'.join([x['id'],b64(x['source']),b64(x['remote']),'1' if x['static'] else '0',b64(json.dumps(x['flags']))]))
        return
    if a.command=='files':
        for x in o['files']: print('\t'.join([b64(x['source']),b64(x['remote']),str(x['mode'])]))
        return
    if a.command=='modules':
        for m in o['modules']: print('\t'.join([m['id'],b64(m['source_dir']),b64(m['args']),'1' if m['unload_after'] else '0',m['name']]))
        return
    if a.command=='module-policies':
        for m in o['modules']: print('\t'.join([m['id'],'1' if m['auto_load'] else '0']))
        return
    if a.command=='panic-expectation':
        x=o.get('expected_panic')
        if x: print('\t'.join([x['module'],b64(x['pattern']),str(int(x['timeout_seconds'])*1000)]))
        return
    if a.command=='processes':
        for p in o['processes']:
            br=p.get('barrier') or {}
            print('\t'.join([p['id'],b64(p['command']),str(int(p['timeout_seconds'])*1000),str(int(p['expected_exit'])),str(br.get('name','')),str(int(br.get('count',0) or 0)),str(int(br.get('timeout_seconds',p['timeout_seconds']))*1000)]))
        return
if __name__=='__main__': main()
