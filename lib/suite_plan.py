#!/usr/bin/env python3
"""Validate KLab suite v2 manifests and materialize target-specific scenarios."""
import argparse,json,os,re
SAFE=re.compile(r'^[A-Za-z0-9._:+-]+$')
def inside(root,value,label):
    if not isinstance(value,str) or not value: raise SystemExit(f'missing {label}')
    path=os.path.realpath(value if os.path.isabs(value) else os.path.join(root,value))
    if os.path.commonpath([root,path]) != root: raise SystemExit(f'{label} escapes suite directory')
    if not os.path.isfile(path): raise SystemExit(f'missing {label}: {value}')
    return path
def load(path):
    root=os.path.realpath(os.path.dirname(path)); o=json.load(open(path,encoding='utf-8'))
    if o.get('schema')!='klab-suite-v2': raise SystemExit('expected klab-suite-v2')
    if not isinstance(o.get('name'),str) or not o['name']: raise SystemExit('suite name is required')
    scenario=inside(root,o.get('scenario'),'scenario'); targets=o.get('targets',[])
    if not isinstance(targets,list): raise SystemExit('suite targets must be a list')
    norm=[]
    for i,x in enumerate(targets):
        if isinstance(x,str):
            if '@' not in x: raise SystemExit(f'target {i} must use TARGET@ARCH')
            target,arch=x.rsplit('@',1)
        elif isinstance(x,dict): target,arch=x.get('target'),x.get('arch')
        else: raise SystemExit(f'invalid target {i}')
        if not isinstance(target,str) or not SAFE.match(target) or not isinstance(arch,str) or not SAFE.match(arch): raise SystemExit(f'invalid target {i}')
        norm.append((target,arch))
    return root,o,scenario,norm
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('command',choices=['validate','targets','scenario']); ap.add_argument('manifest'); ap.add_argument('extra',nargs='*'); a=ap.parse_args()
    root,o,scenario,targets=load(a.manifest)
    if a.command=='validate': print(scenario); return
    if a.command=='targets':
        for target,arch in targets: print(f'{target}\t{arch}')
        return
    if len(a.extra)!=3: raise SystemExit('scenario needs OUTPUT TARGET ARCH')
    out,target,arch=a.extra; s=json.load(open(scenario,encoding='utf-8')); s['target']=target; s['arch']=arch; base=os.path.dirname(scenario)
    for coll,field in (('builds','source'),('modules','source_dir'),('files','source')):
        for item in s.get(coll,[]):
            value=item.get(field)
            if isinstance(value,str) and value and not os.path.isabs(value): item[field]=os.path.normpath(os.path.join(base,value))
    with open(out,'w',encoding='utf-8') as f: json.dump(s,f,indent=2,sort_keys=True); f.write('\n')
if __name__=='__main__': main()
