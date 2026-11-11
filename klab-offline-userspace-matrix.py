#!/usr/bin/env python3
"""Resumable, bounded, inventory-driven offline userspace validation matrix."""
import argparse, csv, datetime, fcntl, hashlib, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

FIELDS = ['target','arch','family','quick_mode','minimal_mode','full_mode','ssh_mode','network_mode','result','started_utc','finished_utc','report','log']

def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def gate_result(gates, name): return gates.get(name, 'NOT_RUN')
def all_pass(gates, names):
    vals=[gate_result(gates,n) for n in names]
    return 'PASS' if vals and all(x=='PASS' for x in vals) else ('FAIL' if any(x=='FAIL' for x in vals) else 'NOT_RUN')
def safe_name(target, arch):
    prefix=''.join(c if c.isalnum() or c in '._-' else '-' for c in f'{target}-{arch}')[:120]
    digest=hashlib.sha256((target+'\0'+arch).encode()).hexdigest()[:12]
    return f'{prefix}-{digest}'

def summarize(report, target):
    gates={}
    gp=report/'gates.tsv'
    if gp.is_file():
        with gp.open(newline='') as f:
            gates={r['GATE']:r['RESULT'] for r in csv.DictReader(f,delimiter='\t')}
    provider=target.split(':',1)[0]
    if provider in {'netbsd','openbsd','dragonfly'} or target.startswith('freebsd:14.5-RELEASE:i386') or target.startswith('freebsd:14.5-RELEASE:riscv64'):
        return (gate_result(gates,'quick_boot'), 'NOT_APPLICABLE', gate_result(gates,'bsd_userspace'), gate_result(gates,'bsd_ssh'), 'NOT_APPLICABLE')
    if provider=='freebsd':
        return (gate_result(gates,'quick_boot'), 'NOT_APPLICABLE', all_pass(gates,['bsd_boot','bsd_conformance']), gate_result(gates,'bsd_ssh'), 'NOT_APPLICABLE')
    return (gate_result(gates,'quick_boot'), gate_result(gates,'module_process'), all_pass(gates,['interactive_boot','userspace_conformance']), gate_result(gates,'interactive_ssh'), gate_result(gates,'two_guest_tcp'))

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('inventory',type=Path); ap.add_argument('outdir',type=Path)
    ap.add_argument('--workers',type=int,default=int(os.environ.get('KLAB_MATRIX_WORKERS','2')))
    ap.add_argument('--timeout',type=int,default=int(os.environ.get('KLAB_MATRIX_TARGET_TIMEOUT','5400')))
    ap.add_argument('--limit',type=int,default=int(os.environ.get('KLAB_MATRIX_LIMIT','0')))
    ap.add_argument('--klab',type=Path,default=Path(__file__).resolve().parent/'klab')
    a=ap.parse_args()
    a.inventory=a.inventory.resolve(); a.outdir=a.outdir.resolve(); a.klab=a.klab.resolve()
    if a.workers < 1: ap.error('--workers must be positive')
    if not (a.klab.is_file() and os.access(a.klab, os.X_OK)): ap.error(f'--klab is not executable: {a.klab}')
    a.outdir.mkdir(parents=True,exist_ok=True); (a.outdir/'reports').mkdir(exist_ok=True); (a.outdir/'logs').mkdir(exist_ok=True)
    lock=(a.outdir/'controller.lock').open('w');
    try: fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError: raise SystemExit(f'another controller holds {a.outdir}/controller.lock')
    status=a.outdir/'status.tsv'; passed=set()
    if status.is_file():
        with status.open(newline='') as f:
            for r in csv.DictReader(f,delimiter='\t'):
                if r.get('result')=='PASS': passed.add((r['target'],r['arch']))
    else:
        with status.open('w',newline='') as f: csv.DictWriter(f,FIELDS,delimiter='\t',lineterminator='\n').writeheader()
    with a.inventory.open(newline='') as f:
        items=[]; seen=set()
        for r in csv.DictReader(f,delimiter='\t'):
            key=(r['target'],r['arch'])
            if key in seen or key in passed: continue
            seen.add(key); items.append((r['target'],r['arch'],r.get('family','')))
    if a.limit: items=items[:a.limit]
    env=os.environ.copy(); env.update(KLAB_OFFLINE='1',KLAB_PREFER_IMPORTED='1')
    def run(item):
        target,arch,family=item; started=now(); safe=safe_name(target,arch)
        stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        report=a.outdir/'reports'/safe/f'attempt-{stamp}'; log=a.outdir/'logs'/f'{safe}-{stamp}.log'; report.mkdir(parents=True,exist_ok=True)
        cmd=[str(a.klab),'validate',target,'--arch',arch,'--level','full','--report-dir',str(report)]
        rc=124
        with log.open('wb') as out:
            try: rc=subprocess.run(cmd,env=env,stdout=out,stderr=subprocess.STDOUT,timeout=a.timeout).returncode
            except subprocess.TimeoutExpired: out.write(f'\nKLAB_MATRIX_TIMEOUT={a.timeout}\n'.encode())
            except Exception as e: out.write(f'\nKLAB_MATRIX_ERROR={e}\n'.encode())
        result=(report/'RESULT').read_text().strip() if (report/'RESULT').is_file() else ('PASS' if rc==0 else 'FAIL')
        quick,minimal,full,ssh,network=summarize(report,target)
        return dict(target=target,arch=arch,family=family,quick_mode=quick,minimal_mode=minimal,full_mode=full,ssh_mode=ssh,network_mode=network,result=result,started_utc=started,finished_utc=now(),report=str(report),log=str(log))
    print(f'queue={len(items)} already_pass={len(passed)} workers={a.workers} offline=1',flush=True)
    failures=0
    with ThreadPoolExecutor(max_workers=a.workers) as pool:
        futures={pool.submit(run,x):x for x in items}
        for future in as_completed(futures):
            row=future.result(); failures += row['result']!='PASS'
            with status.open('a',newline='') as f: csv.DictWriter(f,FIELDS,delimiter='\t',lineterminator='\n').writerow(row)
            print(f"{row['result']}\t{row['target']}\t{row['arch']}\tquick={row['quick_mode']} minimal={row['minimal_mode']} full={row['full_mode']} ssh={row['ssh_mode']}",flush=True)
    print(f'complete={len(items)} failures={failures} status={status}',flush=True)
    return 1 if failures else 0
if __name__=='__main__': sys.exit(main())
