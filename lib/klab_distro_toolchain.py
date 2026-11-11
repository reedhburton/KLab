#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, os, pathlib, shutil, subprocess, tarfile, tempfile, time

FORMAT='kernel-lab-distro-toolchain'; VERSION=3; SUPPORTED={1,2,3}

def die(m): raise SystemExit(f'klab-distro-toolchain: ERROR: {m}')
def sha(p):
 h=hashlib.sha256()
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
 return h.hexdigest()
def canon(o): return json.dumps(o,sort_keys=True,separators=(',',':')).encode()
def aid(spec): return hashlib.sha256(canon(spec)).hexdigest()
def safe_rel(n):
 p=pathlib.PurePosixPath(n)
 if not n or p.is_absolute() or '..' in p.parts: die(f'unsafe artifact path: {n}')
 return str(p)
def safe_root_path(n,key):
 p=pathlib.PurePosixPath(n)
 if not p.is_absolute() or '..' in p.parts: die(f'compiler metadata {key} must be an absolute distro-root path: {n}')
 return str(p)
def pkg_files(d): return sorted([p for p in pathlib.Path(d).iterdir() if p.is_file() and p.suffix in ('.deb','.rpm','.apk')],key=lambda p:p.name)
def package_set_sha(pk):
 h=hashlib.sha256()
 for p in pkg_files(pk): h.update(p.name.encode()+b'\0'+sha(p).encode()+b'\0')
 return h.hexdigest()
def validate_inventory(p):
 rows=[]; seen=set()
 for i,line in enumerate(pathlib.Path(p).read_text().splitlines(),1):
  if not line.strip(): continue
  cols=line.split('\t')
  if len(cols)!=3 or any(not x or '\x00' in x or '\n' in x for x in cols): die(f'malformed package inventory row {i}')
  name,version,arch=cols
  if '/' in name or name in ('.','..'): die(f'unsafe package name in inventory row {i}: {name}')
  row=tuple(cols)
  if row in seen: die(f'duplicate package inventory row {i}: {line}')
  seen.add(row); rows.append(row)
 if not rows: die('package inventory missing or empty')
 return rows
def validate_compiler(p):
 try: c=json.loads(pathlib.Path(p).read_text())
 except Exception as e: die(f'invalid compiler metadata: {e}')
 for k in ('cc_version','cc_target','as_version','ld_version','cc_path','as_path','ld_path'):
  if not isinstance(c.get(k),str) or not c[k].strip(): die(f'compiler metadata missing {k}')
 for k in ('cc_path','as_path','ld_path'): safe_root_path(c[k],k)
 return c
def validate_provenance(p, provider=None, release=None, packages=None):
 try: x=json.loads(pathlib.Path(p).read_text())
 except Exception as e: die(f'invalid repository provenance: {e}')
 if not isinstance(x,dict) or x.get('schema')!='klab-repository-provenance-v1': die('invalid repository provenance schema')
 for k in ('provider','release','repository_config_sha256','key_inventory_sha256','repository_metadata_sha256'):
  if not isinstance(x.get(k),str) or not x[k].strip(): die(f'repository provenance missing {k}')
 for k in ('repository_config_sha256','key_inventory_sha256','repository_metadata_sha256'):
  if len(x[k])!=64 or any(c not in '0123456789abcdef' for c in x[k]): die(f'invalid {k}')
 if provider is not None and x['provider'] != provider: die(f'repository provenance provider mismatch: expected {provider}, got {x["provider"]}')
 if release is not None and x['release'] != release: die(f'repository provenance release mismatch: expected {release}, got {x["release"]}')
 # Do not merely content-address the provenance JSON: verify that its embedded
 # digest claims actually describe the embedded evidence.  Otherwise a valid
 # artifact could faithfully preserve a false repository/key digest claim.
 def text_sha(v): return hashlib.sha256(v.encode()).hexdigest()
 if not isinstance(x.get('repository_config'),str) or text_sha(x['repository_config']) != x['repository_config_sha256']:
  die('repository provenance config digest does not match embedded repository configuration')
 if not isinstance(x.get('key_inventory'),str) or text_sha(x['key_inventory']) != x['key_inventory_sha256']:
  die('repository provenance key digest does not match embedded key inventory')
 meta=x.get('repository_metadata')
 if not isinstance(meta,list): die('repository provenance metadata inventory must be a list')
 # Capture writers use compact JSON in this digest; retain that encoding as the
 # v1 schema contract and validate each [path, sha256] row before hashing it.
 for i,row in enumerate(meta,1):
  if not isinstance(row,list) or len(row)!=2 or not all(isinstance(v,str) and v for v in row): die(f'malformed repository metadata row {i}')
  if len(row[1])!=64 or any(c not in '0123456789abcdef' for c in row[1]): die(f'invalid repository metadata digest row {i}')
 if text_sha(json.dumps(meta,separators=(',',':'))) != x['repository_metadata_sha256']:
  die('repository provenance metadata digest does not match embedded metadata inventory')
 # APT authenticates packages through signed repository metadata rather than
 # per-DEB signatures.  When capture provides the final Packages-stanza link,
 # require exact coverage of the retained DEBs and exact package identity/hash.
 aptmeta=x.get('apt_package_metadata')
 if aptmeta is not None:
  if not isinstance(aptmeta,list): die('repository provenance apt_package_metadata must be a list')
  byfile={}; identities=set()
  for i,row in enumerate(aptmeta,1):
   if not isinstance(row,dict): die(f'malformed APT package metadata row {i}')
   n=row.get('name'); v=row.get('version'); a=row.get('arch'); f=row.get('file'); local_sha=row.get('sha256')
   # Legacy v1 rows used sha256 as both the authenticated Packages digest and
   # the local content binding. New rows state the metadata algorithm explicitly.
   alg=row.get('metadata_digest_algorithm','SHA256'); d=row.get('metadata_digest',local_sha)
   if not all(isinstance(q,str) and q for q in (n,v,a,f,local_sha,alg,d)): die(f'incomplete APT package metadata row {i}')
   if pathlib.PurePosixPath(f).name != f or not f.endswith('.deb'): die(f'invalid APT package filename row {i}')
   if f in byfile: die(f'duplicate APT package metadata for {f}')
   if len(local_sha)!=64 or any(c not in '0123456789abcdef' for c in local_sha): die(f'invalid local APT package SHA256 row {i}')
   lengths={'SHA256':64,'SHA1':40,'MD5sum':32}
   if alg not in lengths or len(d)!=lengths[alg] or any(c not in '0123456789abcdef' for c in d): die(f'invalid authenticated APT package digest row {i}')
   ident=(n,v,a)
   if ident in identities: die(f'duplicate APT package identity row {i}')
   identities.add(ident); byfile[f]=row
  if packages is not None:
   actual={q.name:q for q in pkg_files(packages) if q.suffix=='.deb'}
   if set(byfile)!=set(actual): die('APT package metadata does not exactly cover captured DEB set')
   for n,q in actual.items():
    row=byfile[n]
    if row['sha256'] != sha(q): die(f'APT local SHA256 mismatch: {n}')
    alg=row.get('metadata_digest_algorithm','SHA256'); expected=row.get('metadata_digest',row['sha256'])
    hname={'SHA256':'sha256','SHA1':'sha1','MD5sum':'md5'}[alg]
    h=hashlib.new(hname)
    with q.open('rb') as fh:
     for chunk in iter(lambda:fh.read(1024*1024),b''): h.update(chunk)
    if h.hexdigest()!=expected: die(f'authenticated APT metadata digest mismatch: {n}')
 # RPM captures may carry package-level signature evidence.  When present it is
 # not advisory: every RPM must be covered exactly once, its captured digest
 # must still match, and the capture-time signature check must have succeeded.
 sigs=x.get('package_signatures')
 if sigs is not None:
  if not isinstance(sigs,list): die('repository provenance package_signatures must be a list')
  byname={}
  for i,row in enumerate(sigs,1):
   if not isinstance(row,dict): die(f'malformed package signature row {i}')
   n=row.get('file'); d=row.get('sha256'); ok=row.get('verified'); ev=row.get('evidence')
   if not isinstance(n,str) or pathlib.PurePosixPath(n).name != n or not n.endswith('.rpm'): die(f'invalid package signature filename row {i}')
   if n in byname: die(f'duplicate package signature evidence for {n}')
   if not isinstance(d,str) or len(d)!=64 or any(c not in '0123456789abcdef' for c in d): die(f'invalid package signature digest row {i}')
   if ok is not True: die(f'RPM signature was not verified during capture: {n}')
   if not isinstance(ev,str) or not ev.strip(): die(f'missing RPM signature evidence: {n}')
   byname[n]=row
  if packages is not None:
   actual={q.name:q for q in pkg_files(packages) if q.suffix=='.rpm'}
   if set(byname)!=set(actual): die('RPM signature evidence does not exactly cover captured RPM set')
   for n,q in actual.items():
    if byname[n]['sha256'] != sha(q): die(f'RPM signature evidence digest mismatch: {n}')
 return x

def spec_for(provider,release,arch,inv,comp,pk,version=VERSION,prov=None):
 d={'format':FORMAT,'format_version':version,'artifact_type':'distro-toolchain','provider':provider,'release':release,'arch':arch,
         'package_inventory_sha256':sha(inv),'compiler_metadata_sha256':sha(comp),'package_set_sha256':package_set_sha(pk)}
 if prov is not None: d['repository_provenance_sha256']=sha(prov)
 return d
def expected_names(pk,version=VERSION):
 base={'FORMAT_VERSION','manifest.json','SHA256SUMS','spec','packages','spec/packages.tsv','spec/compiler.json'} | {f'packages/{p.name}' for p in pkg_files(pk)}
 if version>=3: base.add('spec/provenance.json')
 return base
def write_outer(stage,out):
 subprocess.run(['tar','-C',str(stage),'--sort=name','--mtime=@0','--owner=0','--group=0','--numeric-owner','--zstd','-cf',str(out),'FORMAT_VERSION','manifest.json','SHA256SUMS','spec','packages'],check=True)
def extract(file,dest): subprocess.run(['tar','--zstd','-xf',str(file),'-C',str(dest),'--no-same-owner'],check=True)
def archive_names(file):
 p=subprocess.Popen(['zstd','-dc',str(file)],stdout=subprocess.PIPE); names=set(); completed=False
 try:
  with tarfile.open(fileobj=p.stdout,mode='r|') as tf:
   for m in tf:
    n=m.name
    while n.startswith('./'): n=n[2:]
    if not n: continue
    n=safe_rel(n.rstrip('/'))
    if m.isdev() or m.isfifo() or m.issym() or m.islnk(): die(f'non-regular archive entry rejected: {n}')
    if not (m.isdir() or m.isreg()): die(f'unsupported archive entry rejected: {n}')
    if n in names: die(f'duplicate archive entry: {n}')
    names.add(n)
  completed=True
 finally:
  if p.stdout: p.stdout.close()
  rc=p.wait()
  if completed and rc: die('could not read compressed artifact')
 return names
def verify_dir(tmp, require_dir_name=None):
 tmp=pathlib.Path(tmp)
 try: version=int((tmp/'FORMAT_VERSION').read_text().strip())
 except Exception: die('invalid format version')
 if version not in SUPPORTED: die('unsupported format version')
 try: m=json.loads((tmp/'manifest.json').read_text())
 except Exception as e: die(f'invalid manifest: {e}')
 if m.get('format')!=FORMAT or m.get('format_version')!=version or m.get('artifact_type')!='distro-toolchain': die('invalid manifest')
 pk=tmp/'packages'; inv=tmp/'spec/packages.tsv'; comp=tmp/'spec/compiler.json'
 if not pk.is_dir() or not pkg_files(pk): die('artifact contains no distro packages')
 validate_inventory(inv); c=validate_compiler(comp)
 prov=tmp/'spec/provenance.json'
 if version>=3:
  validate_provenance(prov,m.get('provider',''),m.get('release',''),pk)
 rows={}
 for line in (tmp/'SHA256SUMS').read_text().splitlines():
  if not line.strip(): continue
  parts=line.split(None,1)
  if len(parts)!=2: die('malformed SHA256SUMS')
  s,n=parts; n=safe_rel(n.lstrip('*').strip())
  if n in rows: die(f'duplicate checksum path: {n}')
  rows[n]=s
 expected_files={'manifest.json','spec/packages.tsv','spec/compiler.json'}|{f'packages/{p.name}' for p in pkg_files(pk)}
 if version>=3: expected_files.add('spec/provenance.json')
 if set(rows)!=expected_files: die('checksum manifest does not exactly cover distro toolchain payload')
 for n,s in rows.items():
  if sha(tmp/n)!=s: die(f'checksum mismatch: {n}')
 spec=spec_for(m.get('provider',''),m.get('release',''),m.get('arch',''),inv,comp,pk,version,prov if version>=3 else None)
 if aid(spec)!=m.get('id'): die('content/spec ID mismatch')
 if m.get('compiler') != c: die('manifest compiler metadata does not match spec/compiler.json')
 if require_dir_name is not None and pathlib.Path(require_dir_name).name != m['id']: die('installed distro-toolchain ID/path mismatch')
 return m
def verify(file):
 file=pathlib.Path(file)
 if not file.is_file(): die(f'artifact not found: {file}')
 names=archive_names(file); tmp=pathlib.Path(tempfile.mkdtemp(prefix='klab-distro-tc-'))
 try:
  extract(file,tmp); m=verify_dir(tmp)
  expected=expected_names(tmp/'packages',int((tmp/'FORMAT_VERSION').read_text().strip()))
  if names!=expected: die(f'artifact member set mismatch: unexpected={sorted(names-expected)} missing={sorted(expected-names)}')
  return m
 finally: shutil.rmtree(tmp,ignore_errors=True)
from klab_paths import root_home

def object_dir(home,ident): return pathlib.Path(home)/'artifacts/distro-toolchains/sha256'/ident
def cmd_create(a):
 pk=pathlib.Path(a.packages).resolve(); inv=pathlib.Path(a.inventory).resolve(); comp=pathlib.Path(a.compiler_json).resolve()
 if not pk.is_dir() or not pkg_files(pk): die('package directory contains no .deb/.rpm files')
 validate_inventory(inv); c=validate_compiler(comp)
 prov=pathlib.Path(a.provenance).resolve() if a.provenance else None
 version=3 if prov else 2
 if prov: validate_provenance(prov,a.provider,a.release,pk)
 spec=spec_for(a.provider,a.release,a.arch,inv,comp,pk,version,prov); ident=aid(spec); stage=pathlib.Path(tempfile.mkdtemp(prefix='klab-distro-tc-create-'))
 try:
  (stage/'spec').mkdir(); (stage/'packages').mkdir(); (stage/'FORMAT_VERSION').write_text(f'{version}\n')
  shutil.copy2(inv,stage/'spec/packages.tsv'); shutil.copy2(comp,stage/'spec/compiler.json')
  if prov: shutil.copy2(prov,stage/'spec/provenance.json')
  for p in pkg_files(pk): shutil.copy2(p,stage/'packages'/p.name)
  m=dict(spec); m.update({'id':ident,'created_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'compiler':c})
  (stage/'manifest.json').write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
  paths=['manifest.json','spec/packages.tsv','spec/compiler.json']+(['spec/provenance.json'] if prov else [])+[f'packages/{p.name}' for p in pkg_files(stage/'packages')]
  (stage/'SHA256SUMS').write_text(''.join(f'{sha(stage/n)}  {n}\n' for n in paths))
  out=pathlib.Path(a.output or f'distro-toolchain-{a.provider}-{a.release}-{a.arch}--{ident[:16]}.klabdistrotoolchain').resolve(); out.parent.mkdir(parents=True,exist_ok=True)
  write_outer(stage,out); verify(out); print(f'{ident}\t{out}')
 finally: shutil.rmtree(stage,ignore_errors=True)
def cmd_verify(a): print(verify(a.file)['id'])
def cmd_inspect(a): print(json.dumps(verify(a.file),indent=2,sort_keys=True))
def cmd_import(a):
 m=verify(a.file); home=pathlib.Path(root_home(a.home)).resolve(); dest=object_dir(home,m['id']); dest.parent.mkdir(parents=True,exist_ok=True)
 if dest.exists():
  try:
   verify_dir(dest, dest)
   print(dest); return
  except SystemExit:
   if not a.force: die(f'installed distro-toolchain {m["id"]} failed integrity verification; use --force to replace')
   shutil.rmtree(dest)
 tmp=pathlib.Path(tempfile.mkdtemp(prefix='klab-distro-tc-import-',dir=str(dest.parent)))
 try:
  extract(a.file,tmp); verify_dir(tmp); os.replace(tmp,dest); verify_dir(dest,dest); print(dest)
 except Exception:
  shutil.rmtree(tmp,ignore_errors=True); raise
def cmd_lookup(a):
 d=object_dir(root_home(a.home),a.id); verify_dir(d,d); print(d)
def cmd_assert(a):
 d=object_dir(root_home(a.home),a.id); m=verify_dir(d,d)
 for key,val in (('provider',a.provider),('release',a.release),('arch',a.arch)):
  if val and str(m.get(key,''))!=val: die(f'installed distro-toolchain binding mismatch for {key}: expected {val}, got {m.get(key) or "<empty>"}')
 if a.json: print(json.dumps(m,sort_keys=True,separators=(',',':')))
 else: print(d)
def cmd_list(a):
 base=pathlib.Path(root_home(a.home))/'artifacts/distro-toolchains/sha256'
 if not base.is_dir(): return
 for d in sorted(base.iterdir()):
  if not d.is_dir(): continue
  try:
   m=verify_dir(d,d); print(f"{m['id']}\t{m['provider']}:{m['release']}\t{m['arch']}\t{m['compiler']['cc_version']}\tbinutils-as={m['compiler']['as_version']}")
  except SystemExit: continue
def version_tuple(s):
 import re
 m=re.search(r'\d+(?:\.\d+)+',s or '')
 return tuple(int(x) for x in m.group(0).split('.')) if m else ()
def cmd_match_compiler(a):
 m=verify(a.file); actual=version_tuple(m['compiler']['cc_version']); required=version_tuple(a.version)
 if not actual or not required: die('could not parse compiler version for comparison')
 if a.mode=='exact': ok=actual==required
 elif a.mode=='compatible':
  # Compatible means same GCC major/minor.
  ok=len(actual)>=2 and len(required)>=2 and actual[:2]==required[:2]
 else:
  # Distro repositories commonly retain the GCC major used for a kernel while
  # replacing its patch/minor release. This mode is opt-in and is paired with
  # KLab's module compile, vermagic, insertion, and workload gates.
  ok=actual[0]==required[0]
 if not ok: die(f'compiler {a.mode} match failed: kernel requires GCC {a.version}, captured {m["compiler"]["cc_version"]}')
 print(m['compiler']['cc_version'])

def main():
 ap=argparse.ArgumentParser(); sp=ap.add_subparsers(dest='cmd',required=True)
 p=sp.add_parser('create'); p.add_argument('--packages',required=True); p.add_argument('--inventory',required=True); p.add_argument('--compiler-json',required=True); p.add_argument('--provenance'); p.add_argument('--provider',required=True); p.add_argument('--release',required=True); p.add_argument('--arch',required=True); p.add_argument('-o','--output'); p.set_defaults(func=cmd_create)
 p=sp.add_parser('verify'); p.add_argument('file'); p.set_defaults(func=cmd_verify)
 p=sp.add_parser('inspect'); p.add_argument('file'); p.set_defaults(func=cmd_inspect)
 p=sp.add_parser('import'); p.add_argument('file'); p.add_argument('--home'); p.add_argument('--force',action='store_true'); p.set_defaults(func=cmd_import)
 p=sp.add_parser('lookup'); p.add_argument('id'); p.add_argument('--home'); p.set_defaults(func=cmd_lookup)
 p=sp.add_parser('assert-installed'); p.add_argument('id'); p.add_argument('--home'); p.add_argument('--provider'); p.add_argument('--release'); p.add_argument('--arch'); p.add_argument('--json',action='store_true'); p.set_defaults(func=cmd_assert)
 p=sp.add_parser('list'); p.add_argument('--home'); p.set_defaults(func=cmd_list)
 p=sp.add_parser('match-compiler'); p.add_argument('file'); p.add_argument('--version',required=True); p.add_argument('--mode',choices=('exact','compatible','major-compatible'),default='exact'); p.set_defaults(func=cmd_match_compiler)
 a=ap.parse_args(); a.func(a)
if __name__=='__main__': main()
