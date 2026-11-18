#!/usr/bin/env python3
"""Capture audited local source trees/archives as shared .klabsource objects."""
import argparse,csv,json,os,re,subprocess,tempfile
from pathlib import Path

def safe(s): return re.sub(r'[^A-Za-z0-9._+-]+','-',s).strip('-')
def atomic_json(path,obj):
    tmp=path.with_suffix(path.suffix+'.tmp'); tmp.write_text(json.dumps(obj,indent=2,sort_keys=True)+'\n'); os.replace(tmp,path)
def atomic_bindings(path,rows):
    tmp=path.with_suffix(path.suffix+'.tmp')
    fields=['target','arch','source_coverage','source_id','artifact','source_provenance']
    with tmp.open('w',newline='') as h:
        w=csv.DictWriter(h,fields,delimiter='\t',lineterminator='\n'); w.writeheader(); w.writerows(sorted(rows,key=lambda x:(x['target'],x['arch'])))
    os.replace(tmp,path)
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--coverage',required=True,type=Path); ap.add_argument('--repo',required=True,type=Path); ap.add_argument('--klab',required=True,type=Path); ap.add_argument('--state',required=True,type=Path); a=ap.parse_args()
    a.state.mkdir(parents=True,exist_ok=True); outdir=a.repo/'sources'; outdir.mkdir(parents=True,exist_ok=True)
    statefile=a.state/'capture-state.json'; bindingfile=a.repo/'catalog/SOURCE_BINDINGS.tsv'; bindingfile.parent.mkdir(parents=True,exist_ok=True)
    state=json.loads(statefile.read_text()) if statefile.exists() else {'paths':{}}
    bindings=[]
    if bindingfile.exists(): bindings=list(csv.DictReader(bindingfile.open(),delimiter='\t'))
    bykey={(x['target'],x['arch']):x for x in bindings}
    rows=list(csv.DictReader(a.coverage.open(),delimiter='\t'))
    eligible=[x for x in rows if x['source_coverage'] in {'full-source','full-source-archive'} and x['source_path']]
    for i,row in enumerate(eligible,1):
        src=Path(row['source_path']).resolve(); key=str(src); target=row['target']; arch=row['arch']; provider=target.split(':',1)[0]; release=target.split(':')[1] if ':' in target else ''
        cached=state['paths'].get(key)
        if cached and Path(cached['artifact']).is_file(): oid=cached['source_id']; artifact=cached['artifact']
        else:
            with tempfile.NamedTemporaryFile(prefix='.source-',suffix='.klabsource',dir=outdir,delete=False) as h: tmp=Path(h.name)
            tmp.unlink()
            cmd=[str(a.klab/'klab-artifact.sh'),'create','source','--from',str(src),'--name',safe(f'{provider}-{release}-source'),'--arch',arch,'--provider',provider,'--release',release,'--kernel-release',target.split(':')[-1],'--provenance',row['source_provenance'],'-o',str(tmp)]
            subprocess.run(cmd,check=True,stdout=subprocess.DEVNULL)
            oid=subprocess.check_output([str(a.klab/'klab-artifact.sh'),'id',str(tmp)],text=True).strip()
            final=outdir/f'{safe(provider+"-"+release+"-source")}--{oid.split(":",1)[1][:12]}.klabsource'
            if final.exists():
                existing=subprocess.check_output([str(a.klab/'klab-artifact.sh'),'id',str(final)],text=True).strip()
                if existing!=oid: raise SystemExit(f'artifact collision: {final}')
                tmp.unlink()
            else: os.replace(tmp,final)
            artifact=str(final); state['paths'][key]={'source_id':oid,'artifact':artifact}; atomic_json(statefile,state)
        bykey[target,arch]={'target':target,'arch':arch,'source_coverage':'full-source-artifact','source_id':oid,'artifact':artifact,'source_provenance':row['source_provenance']}
        atomic_bindings(bindingfile,list(bykey.values()))
        print(f'[{i}/{len(eligible)}] {target}@{arch} {oid}',flush=True)
    print(f'captured_bindings={len(bykey)} unique_sources={len(state["paths"])}')
if __name__=='__main__': main()
