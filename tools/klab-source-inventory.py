#!/usr/bin/env python3
"""Audit exact targets for full source, module build trees, and source bindings."""
import argparse,csv,hashlib,os,shlex
from pathlib import Path

def envread(path):
    out={}
    try: lines=path.read_text(errors='replace').splitlines()
    except OSError: return out
    for line in lines:
        if not line or line.lstrip().startswith('#') or '=' not in line: continue
        key,val=line.split('=',1)
        if not key.replace('_','').isalnum(): continue
        try:
            words=shlex.split(val, posix=True)
            out[key]=words[0] if len(words)==1 else val
        except ValueError: out[key]=val.strip("'\"")
    return out

def existing(path):
    if not path: return None
    p=Path(path)
    try: return p.resolve() if p.exists() else None
    except OSError: return None

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--catalog',required=True,type=Path); ap.add_argument('--root',required=True,type=Path); ap.add_argument('--repo',type=Path)
    ap.add_argument('--output',required=True,type=Path); a=ap.parse_args()
    local={}
    base=a.root/'targets/kernels'
    for env in base.glob('*/*/*/*/bundle.env'):
        d=envread(env); provider=d.get('BUNDLE_PROVIDER'); arch=d.get('BUNDLE_ARCH')
        if provider=='upstream': target='upstream:'+d.get('BUNDLE_UPSTREAM_VERSION','')
        else: target=d.get('BUNDLE_TARGET_ID') or ':'.join(filter(None,[provider,d.get('BUNDLE_DISTRO_RELEASE'),d.get('BUNDLE_KERNEL_RELEASE')]))
        bundle=existing(d.get('BUNDLE_DIR'))
        if not target or not arch or not bundle or (bundle/'bundle.env').resolve()!=env.resolve(): continue
        local[target,arch]=(env,d)
    rows=[]
    for r in csv.DictReader(a.catalog.open(),delimiter='\t'):
        key=(r['target'],r['arch']); provider=r['target'].split(':',1)[0]
        coverage='missing'; source_id=''; provenance=''; source_path=''; build_path=''
        if key in local:
            env,d=local[key]; src=existing(d.get('BUNDLE_SOURCE_DIR')); build=existing(d.get('BUNDLE_BUILD_DIR'))
            source_path=str(src or ''); build_path=str(build or '')
            archive=existing(d.get('BUNDLE_SOURCE_ARCHIVE')); bound=d.get('BUNDLE_SOURCE_OBJECT_ID',''); bound_prov=d.get('BUNDLE_SOURCE_PROVENANCE','')
            if src and (src/'Makefile').is_file():
                coverage='full-source'; provenance=bound_prov or ('upstream:'+d.get('BUNDLE_UPSTREAM_REF',d.get('BUNDLE_UPSTREAM_VERSION','')) if provider=='upstream' else 'local-source-tree')
                source_id=bound or (('ref:'+d.get('BUNDLE_UPSTREAM_REF')) if d.get('BUNDLE_UPSTREAM_REF') else '')
            elif archive:
                coverage='full-source-archive'; source_path=str(archive); provenance=f'official {provider} source archive'
            elif build: coverage='module-build-tree'; provenance='exact module build tree only'
            if bound: source_id=bound; coverage='full-source-artifact'
        elif provider in {'freebsd','netbsd','openbsd','dragonfly'}:
            coverage='runtime-only'; provenance='portable BSD runtime artifact'
            if a.repo:
                sources=a.repo/'bsd/sources'; release=r['target'].split(':')[1]
                candidates=[]
                if provider=='netbsd': candidates=[sources/f'netbsd-{release}-syssrc.tgz']
                elif provider=='dragonfly': candidates=[sources/f'dragonfly-v{release}.tar.gz']
                elif provider=='freebsd': candidates=[sources/f'FreeBSD-{release}-src.txz',sources/f'freebsd-{release}-src.txz']
                elif provider=='openbsd': candidates=[sources/f'openbsd-{release}-src.tar.gz',sources/f'openbsd-{release}-sys.tar.gz']
                found=next((x for x in candidates if x.is_file()),None)
                if found: coverage='full-source-archive'; source_path=str(found); provenance=f'official {provider} source archive'
        rows.append({**r,'source_coverage':coverage,'source_id':source_id,'source_provenance':provenance,'source_path':source_path,'build_path':build_path})
    fields=list(rows[0])
    a.output.parent.mkdir(parents=True,exist_ok=True)
    with a.output.open('w',newline='') as h:
        w=csv.DictWriter(h,fields,delimiter='\t',lineterminator='\n'); w.writeheader(); w.writerows(rows)
    from collections import Counter
    c=Counter(x['source_coverage'] for x in rows)
    print('targets=%d '%len(rows)+' '.join(f'{k}={c[k]}' for k in sorted(c)))
if __name__=='__main__': main()
