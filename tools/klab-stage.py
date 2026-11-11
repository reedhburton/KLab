#!/usr/bin/env python3
"""Checksum-verified archive-to-NVMe staging cache for KLab artifacts."""
import argparse, hashlib, json, os, shutil, sys, time
from pathlib import Path
ROOT = Path(os.environ.get("KLAB_ROOT", Path.home()/"klab")).expanduser().resolve()
CONFIG=ROOT/"config/archive-volumes.json"; STATE=ROOT/"state/staged-artifacts.json"; CACHE=ROOT/"cache/staged-artifacts/sha256"
def load(p,d):
    try:return json.loads(p.read_text())
    except FileNotFoundError:return d
def save(p,v):
    p.parent.mkdir(parents=True,exist_ok=True); t=p.with_name(p.name+".tmp"); t.write_text(json.dumps(v,indent=2,sort_keys=True)+"\n"); os.replace(t,p)
def digest(p):
    h=hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda:f.read(8<<20),b""):h.update(b)
    return h.hexdigest()
def volumes():return load(CONFIG,{"schema":"klab-archive-volumes-v1","volumes":[]})
def state():return load(STATE,{"schema":"klab-stage-cache-v1","objects":{}})
def add_volume(path):
    p=Path(path).expanduser().resolve()
    if not p.is_dir():raise SystemExit(f"klab: archive volume is not a directory: {p}")
    c=volumes(); s=str(p)
    if s not in c["volumes"]:c["volumes"].append(s);c["volumes"].sort();save(CONFIG,c)
    print(s)
def archive_source(path):
    p=Path(path).expanduser().resolve()
    if not p.is_file():raise SystemExit(f"klab: archive artifact not found: {p}")
    roots=[Path(x).resolve() for x in volumes()["volumes"]]; rf=ROOT/"config/offline-repo"
    if rf.exists():roots.append(Path(rf.read_text().strip()).expanduser().resolve())
    if not any(p==r or r in p.parents for r in roots):raise SystemExit("klab: source is not beneath a registered archive volume or offline repository")
    return p
def free_bytes():return shutil.disk_usage(CACHE.parent if CACHE.parent.exists() else ROOT).free
def prune(required=0,floor_gib=None):
    floor=int((floor_gib if floor_gib is not None else float(os.environ.get("KLAB_STAGE_FREE_GIB","20")))*(1<<30));s=state();removed=0
    for k,m in sorted(s["objects"].items(),key=lambda x:x[1].get("last_access",0)):
        if free_bytes()>=floor+required:break
        p=Path(m["path"])
        if p.exists():removed+=p.stat().st_size;p.unlink()
        s["objects"].pop(k,None)
    save(STATE,s)
    if free_bytes()<floor+required:raise SystemExit(f"klab: insufficient cache space while preserving {floor//(1<<30)} GiB free-space floor")
    return removed
def stage(path):
    src=archive_source(path);size=src.stat().st_size;sha=digest(src);CACHE.mkdir(parents=True,exist_ok=True);dest=CACHE/sha/src.name;s=state()
    if dest.exists() and dest.stat().st_size==size and digest(dest)==sha:
        s["objects"][sha]={"path":str(dest),"source":str(src),"size":size,"last_access":int(time.time())};save(STATE,s);print(dest);return
    prune(size);dest.parent.mkdir(parents=True,exist_ok=True);tmp=dest.with_name(dest.name+".partial")
    with src.open("rb") as rf,tmp.open("wb") as wf:shutil.copyfileobj(rf,wf,8<<20);wf.flush();os.fsync(wf.fileno())
    if digest(tmp)!=sha:tmp.unlink(missing_ok=True);raise SystemExit("klab: staged artifact checksum mismatch")
    os.replace(tmp,dest);s=state();s["objects"][sha]={"path":str(dest),"source":str(src),"size":size,"last_access":int(time.time())};save(STATE,s);print(dest)
def status():
    s=state();total=count=0;print("SHA256\tBYTES\tLAST_ACCESS\tSOURCE\tCACHE")
    for sha,m in sorted(s["objects"].items()):
        p=Path(m["path"])
        if p.exists():count+=1;total+=p.stat().st_size;print(f"{sha}\t{p.stat().st_size}\t{m.get('last_access',0)}\t{m.get('source','')}\t{p}")
    print(f"objects={count} bytes={total} free={free_bytes()}",file=sys.stderr)
def main():
    a=argparse.ArgumentParser();s=a.add_subparsers(dest="cmd",required=True);p=s.add_parser("volume-add");p.add_argument("path");s.add_parser("volume-list");p=s.add_parser("stage");p.add_argument("path");p=s.add_parser("prune");p.add_argument("--free-gib",type=float);s.add_parser("status");x=a.parse_args()
    if x.cmd=="volume-add":add_volume(x.path)
    elif x.cmd=="volume-list":print("\n".join(volumes()["volumes"]))
    elif x.cmd=="stage":stage(x.path)
    elif x.cmd=="prune":print(prune(0,x.free_gib))
    else:status()
if __name__=="__main__":main()
