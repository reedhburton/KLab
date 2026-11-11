#!/usr/bin/env python3
import argparse,glob,os,shlex
p=argparse.ArgumentParser(); p.add_argument('--root',default=os.environ.get('KLAB_ROOT',os.path.expanduser('~/klab-data'))); p.add_argument('--output'); a=p.parse_args()
root=os.path.abspath(os.path.expanduser(a.root)); rows=[]
def envread(path):
 d={}
 for line in open(path,errors='replace'):
  if '=' not in line or line.lstrip().startswith('#'): continue
  k,v=line.rstrip('\n').split('=',1)
  try: d[k]=shlex.split(v)[0] if v else ''
  except: d[k]=v.strip("'\"")
 return d
for path in sorted(glob.glob(root+'/targets/kernels/*/*/*/*/bundle.env')):
 rel=path.split('/targets/kernels/',1)[1].split('/'); d=envread(path); provider=rel[0]; release=rel[1]; arch=d.get('BUNDLE_ARCH',rel[2]); kernel=d.get('BUNDLE_KERNEL_RELEASE',rel[3]);
 # Backup/recovery directories retain the canonical kernel release in metadata.
 # Only the directory whose name exactly matches that release is a target row.
 if rel[3] != kernel: continue
 backend=d.get('BUNDLE_BACKEND','freebsd' if provider=='freebsd' else 'linux'); target=d.get('BUNDLE_TARGET_ID',f'{provider}:{release}:{kernel}')
 reasons=[]
 if backend=='linux':
  br=f'{root}/artifacts/userspaces/buildroot/2025.02.18/minimal/{arch}'
  if not os.path.isfile(br+'/rootfs.tar') or not (os.path.isdir(br+'/sdk') or os.path.isfile(br+'/sdk.tar.gz')): reasons.append('missing-minimal-sdk')
  standard='yes' if not reasons else 'no'
  native=f'{root}/artifacts/userspaces/native/{provider}/{release}/{arch}'
  full='yes' if os.path.isfile(native+'/rootfs.tar.zst') and os.path.isfile(native+'/metadata.env') else 'no'
  if full=='no': reasons.append('missing-native-rootfs')
 else:
  caps=d.get('BUNDLE_CAPABILITIES',''); need=('boot','push','exec','module-build','module-load','module-unload')
  standard='yes' if all(x in caps.split(',') for x in need) else 'no'; full=standard
  if standard=='no': reasons.append('missing-freebsd-capabilities')
 rows.append((target,backend,arch,standard,full,','.join(reasons) or '-'))
out='TARGET\tBACKEND\tARCH\tSTANDARD_RUNNABLE\tFULL_RUNNABLE\tREASON\n'+'\n'.join('\t'.join(r) for r in rows)+'\n'
if a.output: open(a.output,'w').write(out)
print(out,end='')
if any(r[3]!='yes' or r[4]!='yes' for r in rows): raise SystemExit(1)
