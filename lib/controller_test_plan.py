#!/usr/bin/env python3
"""Validate and expose the small controller-side KLab test manifest."""
import base64,json,os,re,sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib
NAME=re.compile(r'^[A-Za-z][A-Za-z0-9_.-]*$')
def die(s): raise SystemExit('klab: '+s)
def enc(v):
    if not isinstance(v,str): v=json.dumps(v,separators=(',',':'))
    return base64.b64encode(v.encode()).decode()
def load(path):
    try:
        with open(path,'rb') as f: d=tomllib.load(f)
    except (OSError,tomllib.TOMLDecodeError) as e: die(f'cannot read {path}: {e}')
    t=d.get('test',{})
    if not isinstance(t,dict): die('[test] must be a table')
    if not isinstance(t.get('script','test.sh'),str): die('test.script must be a path')
    if not isinstance(t.get('timeout',300),int) or t.get('timeout',300)<1: die('test.timeout must be a positive integer')
    for kind in ('module','build','file'):
        sec=d.get(kind,{})
        if not isinstance(sec,dict): die(f'[{kind}] entries must be named tables')
        for name,item in sec.items():
            if not NAME.fullmatch(name) or not isinstance(item,dict): die(f'invalid {kind} entry: {name}')
            src=item.get('sources',item.get('source')) if kind=='build' else item.get('source')
            if not isinstance(src,(str,list)) or not src: die(f'{kind}.{name} needs source')
            if isinstance(src,list) and not all(isinstance(x,str) and x for x in src): die(f'{kind}.{name}.sources must be paths')
    return d
def safe(base,p):
    q=os.path.realpath(p if os.path.isabs(p) else os.path.join(base,p))
    if not os.path.isabs(p) and os.path.commonpath((base,q))!=base: die(f'path escapes suite directory: {p}')
    return q
def main():
    if len(sys.argv)!=3: die('internal manifest planner usage')
    cmd,path=sys.argv[1:]; d=load(path); base=os.path.realpath(os.path.dirname(path)); t=d.get('test',{})
    if cmd=='validate':
        script=safe(base,t.get('script','test.sh'))
        if not os.path.isfile(script): die(f'test script not found: {script}')
        print(json.dumps(d,indent=2,sort_keys=True)); return
    if cmd=='meta': print('\t'.join((enc(safe(base,t.get('script','test.sh'))),enc(t.get('userspace','auto')),enc(t.get('profile','normal')),str(t.get('timeout',300))))); return
    if cmd=='modules':
        for n,x in d.get('module',{}).items(): print('\t'.join((n,enc(safe(base,x['source'])),enc(x.get('args','')),str(int(x.get('unload',True))))))
        return
    if cmd=='builds':
        for n,x in d.get('build',{}).items():
            src=x.get('sources',x.get('source')); src=[src] if isinstance(src,str) else src
            flags=x.get('flags',[])
            if not isinstance(flags,list) or not all(isinstance(y,str) for y in flags): die(f'build.{n}.flags must be strings')
            print('\t'.join((n,enc([safe(base,y) for y in src]),str(int(x.get('static',True))),enc(flags),enc(x.get('target',f'/tmp/klab-builds/{n}')))))
        return
    if cmd=='files':
        for n,x in d.get('file',{}).items(): print('\t'.join((n,enc(safe(base,x['source'])),enc(x.get('target',f"/tmp/klab-files/{os.path.basename(x['source'])}")),str(x.get('mode','0644')))))
        return
    die(f'unknown planner command: {cmd}')
if __name__=='__main__': main()
