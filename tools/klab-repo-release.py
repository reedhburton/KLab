#!/usr/bin/env python3
"""Immutable KLab repository snapshots and parent-linked offline delta releases."""
import argparse, datetime, hashlib, json, os, shutil, subprocess, sys, tempfile
from pathlib import Path
SCHEMA='klab-repository-snapshot-v1'
META='.klab-releases'

def digest(path, chunk=8<<20):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        while b:=f.read(chunk): h.update(b)
    return h.hexdigest()

def state(repo):
    d=repo/META; (d/'snapshots').mkdir(parents=True,exist_ok=True); (d/'applied').mkdir(exist_ok=True); return d

def snap_path(repo,name):
    if not name or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-' for c in name): raise SystemExit('invalid release name')
    return state(repo)/'snapshots'/f'{name}.json'

def load(repo,name):
    p=snap_path(repo,name)
    if not p.is_file(): raise SystemExit(f'unknown repository release: {name}')
    return json.loads(p.read_text())

def klab_commit():
    here=Path(__file__).resolve().parent.parent
    try: return subprocess.check_output(['git','-C',str(here),'rev-parse','HEAD'],text=True,stderr=subprocess.DEVNULL).strip()
    except Exception: return 'unknown'

def iter_files(repo):
    for base,dirs,files in os.walk(repo):
        relbase=Path(base).relative_to(repo)
        dirs[:]=sorted(d for d in dirs if not (relbase==Path('.') and d==META))
        for n in sorted(files):
            p=Path(base)/n
            if p.is_symlink() or not p.is_file(): continue
            yield p,p.relative_to(repo).as_posix()

def snapshot(args):
    repo=Path(args.repo).resolve(); repo.mkdir(parents=True,exist_ok=True); out=snap_path(repo,args.name)
    if out.exists(): raise SystemExit(f'release is immutable and already exists: {args.name}')
    parent=load(repo,args.parent) if args.parent else None
    entries=[]
    for p,rel in iter_files(repo):
        before=p.stat(); sha=digest(p); after=p.stat()
        if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns): raise SystemExit(f'file changed while snapshotting: {rel}')
        entries.append({'path':rel,'bytes':after.st_size,'sha256':sha})
    previous={x['path']:x for x in parent['files']} if parent else {}
    current={x['path']:x for x in entries}
    changed=[x for x in entries if previous.get(x['path'],{}).get('sha256')!=x['sha256']]
    removed=sorted(set(previous)-set(current))
    doc={'schema':SCHEMA,'name':args.name,'parent':args.parent,'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
         'klab_commit':klab_commit(),'bundle_format':'kernel-lab-bundle-v1','repository':str(repo),'files':entries,
         'delta':{'changed':[x['path'] for x in changed],'removed':removed}}
    canonical=json.dumps(doc,sort_keys=True,separators=(',',':')).encode(); doc['snapshot_sha256']=hashlib.sha256(canonical).hexdigest()
    tmp=out.with_suffix('.tmp'); tmp.write_text(json.dumps(doc,indent=2,sort_keys=True)+'\n'); os.replace(tmp,out)
    print(f"snapshot={args.name} files={len(entries)} changed={len(changed)} removed={len(removed)} sha256={doc['snapshot_sha256']}")

def squash(args):
    repo=Path(args.repo).resolve(); source=load(repo,args.source); out=snap_path(repo,args.name)
    if out.exists(): raise SystemExit(f'release is immutable and already exists: {args.name}')
    doc=dict(source); doc['name']=args.name; doc['parent']=None
    doc['created_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat(); doc['klab_commit']=klab_commit()
    doc['delta']={'changed':[x['path'] for x in doc['files']],'removed':[]}
    doc.pop('snapshot_sha256',None)
    canonical=json.dumps(doc,sort_keys=True,separators=(',',':')).encode(); doc['snapshot_sha256']=hashlib.sha256(canonical).hexdigest()
    tmp=out.with_suffix('.tmp'); tmp.write_text(json.dumps(doc,indent=2,sort_keys=True)+'\n'); os.replace(tmp,out)
    print(f"snapshot={args.name} files={len(doc['files'])} changed={len(doc['files'])} removed=0 sha256={doc['snapshot_sha256']} source={args.source}")

def export_release(args):
    repo=Path(args.repo).resolve(); doc=load(repo,args.name); out=Path(args.output).resolve()
    paths=doc['delta']['changed'] if doc.get('parent') else [x['path'] for x in doc['files']]
    expected={x['path']:x for x in doc['files']}; stage=state(repo)/f'.stage-{os.getpid()}'
    if stage.exists(): shutil.rmtree(stage)
    (stage/'files').mkdir(parents=True); (stage/'meta').mkdir()
    try:
        for rel in paths:
            src=repo/rel; e=expected[rel]
            if not src.is_file() or src.stat().st_size!=e['bytes'] or digest(src)!=e['sha256']: raise SystemExit(f'repository changed since snapshot: {rel}')
            dst=stage/'files'/rel; dst.parent.mkdir(parents=True,exist_ok=True)
            try: os.link(src,dst)
            except OSError: shutil.copy2(src,dst)
        (stage/'meta'/'release.json').write_text(json.dumps(doc,indent=2,sort_keys=True)+'\n')
        out.parent.mkdir(parents=True,exist_ok=True); tmp=out.with_suffix(out.suffix+'.part')
        subprocess.run(['tar','--zstd','-C',str(stage),'-cf',str(tmp),'.'],check=True); os.replace(tmp,out)
        (out.parent/(out.name+'.sha256')).write_text(f'{digest(out)}  {out.name}\n')
    finally: shutil.rmtree(stage,ignore_errors=True)
    print(f'exported={out} files={len(paths)} parent={doc.get("parent") or "-"}')

def apply_release(args):
    repo=Path(args.repo).resolve(); repo.mkdir(parents=True,exist_ok=True); archive=Path(args.archive).resolve(); st=state(repo)
    with tempfile.TemporaryDirectory(prefix='klab-release-',dir=st) as td:
        subprocess.run(['tar','--zstd','-xf',str(archive),'-C',td],check=True)
        base=Path(td); doc=json.loads((base/'meta'/'release.json').read_text()); parent=doc.get('parent')
        if doc.get('schema')!=SCHEMA: raise SystemExit('unsupported repository release schema')
        if parent and not (st/'applied'/f'{parent}.json').is_file(): raise SystemExit(f'release requires applied parent: {parent}')
        expected={x['path']:x for x in doc['files']}
        for rel in doc['delta']['changed'] if parent else expected:
            src=base/'files'/rel; e=expected[rel]
            if not src.is_file() or src.stat().st_size!=e['bytes'] or digest(src)!=e['sha256']: raise SystemExit(f'invalid release object: {rel}')
        for rel in doc['delta']['changed'] if parent else expected:
            src=base/'files'/rel; dst=repo/rel; dst.parent.mkdir(parents=True,exist_ok=True); tmp=dst.with_name(dst.name+f'.part.{os.getpid()}'); shutil.copy2(src,tmp); os.replace(tmp,dst)
        if args.apply_removals:
            for rel in doc['delta'].get('removed',[]):
                p=repo/rel
                if p.is_file(): p.unlink()
        target=st/'applied'/f"{doc['name']}.json"; target.write_text(json.dumps(doc,indent=2,sort_keys=True)+'\n')
    print(f"applied={doc['name']} parent={parent or '-'}")

def releases(args):
    repo=Path(args.repo).resolve(); print('NAME\tPARENT\tCREATED_UTC\tFILES\tCHANGED\tSHA256')
    for p in sorted((state(repo)/'snapshots').glob('*.json')):
        d=json.loads(p.read_text()); print(f"{d['name']}\t{d.get('parent') or '-'}\t{d['created_utc']}\t{len(d['files'])}\t{len(d['delta']['changed'])}\t{d['snapshot_sha256']}")

def main():
    ap=argparse.ArgumentParser(); sub=ap.add_subparsers(dest='cmd',required=True)
    p=sub.add_parser('snapshot'); p.add_argument('repo'); p.add_argument('name'); p.add_argument('--parent'); p.set_defaults(fn=snapshot)
    p=sub.add_parser('squash'); p.add_argument('repo'); p.add_argument('source'); p.add_argument('name'); p.set_defaults(fn=squash)
    p=sub.add_parser('export'); p.add_argument('repo'); p.add_argument('name'); p.add_argument('-o','--output',required=True); p.set_defaults(fn=export_release)
    p=sub.add_parser('apply'); p.add_argument('repo'); p.add_argument('archive'); p.add_argument('--apply-removals',action='store_true'); p.set_defaults(fn=apply_release)
    p=sub.add_parser('list'); p.add_argument('repo'); p.set_defaults(fn=releases)
    a=ap.parse_args(); a.fn(a)
if __name__=='__main__': main()
