#!/usr/bin/env python3
"""Fast physical KLab artifact scan without rehashing embedded payloads."""
import argparse, csv, json, subprocess
from pathlib import Path

def manifest(path: Path):
    # .klab archives put manifest.json before their large payloads. Read only
    # that tar member from the zstd stream, then terminate decompression.
    proc=subprocess.Popen(['zstd','-dc','--',str(path)],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    stream=proc.stdout
    try:
        longname=None
        while True:
            header=stream.read(512)
            if len(header)!=512 or header==b'\0'*512: return None,'manifest.json absent'
            rawname=header[:100].split(b'\0',1)[0]
            prefix=header[345:500].split(b'\0',1)[0]
            name=(prefix+b'/' if prefix else b'')+rawname
            if longname is not None: name=longname; longname=None
            try: size=int(header[124:136].rstrip(b'\0 ').lstrip() or b'0',8)
            except ValueError: return None,'invalid tar size'
            data=stream.read(size); pad=(-size)%512
            if pad: stream.read(pad)
            if header[156:157]==b'L': longname=data.rstrip(b'\0'); continue
            if name.decode(errors='replace').lstrip('./')=='manifest.json':
                try: return json.loads(data),''
                except Exception as e: return None,str(e)
    finally:
        if stream: stream.close()
        proc.terminate()
        try: proc.wait(timeout=2)
        except subprocess.TimeoutExpired: proc.kill(); proc.wait()

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('repo',type=Path); ap.add_argument('-o','--output',required=True,type=Path); a=ap.parse_args()
    rows=[]
    for f in sorted(a.repo.rglob('*.klab')):
        if '.klab-releases' in f.parts: continue
        m,e=manifest(f)
        rows.append({'file':str(f),'target':(m or {}).get('target',''),'arch':(m or {}).get('arch',''),'kernel_release':(m or {}).get('kernel_release',''),'error':e})
    # BSD simple targets are portable directory artifacts consumed directly by bsd-simple.sh.
    for env in sorted((a.repo/'bsd').glob('*/target.env')):
        target=''
        for line in env.read_text(errors='replace').splitlines():
            if line.startswith('TARGET='): target=line.split('=',1)[1].strip().strip("'\""); break
        arch=target.rsplit(':',1)[-1] if target else ''
        rows.append({'file':str(env.parent),'target':target,'arch':arch,'kernel_release':arch,'error':'' if target else 'missing TARGET'})
    a.output.parent.mkdir(parents=True,exist_ok=True)
    with a.output.open('w',newline='') as h:
        w=csv.DictWriter(h,['file','target','arch','kernel_release','error'],delimiter='\t',lineterminator='\n'); w.writeheader(); w.writerows(rows)
    good=sum(bool(not x['error'] and x['target'] and x['arch']) for x in rows)
    print(f'artifacts={len(rows)} mapped={good} errors={len(rows)-good}')
if __name__=='__main__': main()
