#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, os, pathlib, stat, subprocess, sys

FORMAT='kernel-lab-toolchain-boundary'
VERSION=1
META='.klab-toolchain-boundary.json'
VOLATILE={META,'.klab-toolchain.sha256'}
REQUIRED=('cc1','as','ld','ar','nm','objcopy','objdump','strip','readelf','addr2line','size','strings','ranlib')


def die(msg):
    raise SystemExit(f'klab-toolchain-boundary: ERROR: {msg}')


def sha_file(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(1024*1024), b''): h.update(b)
    return h.hexdigest()


def clean_rel(s, name='path'):
    if not s: die(f'missing {name}')
    p=pathlib.PurePosixPath(s)
    if p.is_absolute() or '..' in p.parts: die(f'unsafe {name}: {s}')
    return str(p)


def real_inside(root, p, name='path'):
    root=pathlib.Path(root).resolve()
    p=pathlib.Path(p)
    if not p.is_absolute(): p=root/p
    try: rp=p.resolve(strict=True)
    except FileNotFoundError: die(f'{name} does not exist: {p}')
    try: rp.relative_to(root)
    except ValueError: die(f'{name} escapes toolchain root: {p} -> {rp}')
    return rp


def validate_tree(root):
    root=pathlib.Path(root).resolve()
    for base, dirs, files in os.walk(root,topdown=True,followlinks=False):
        dirs.sort(); files.sort()
        for name in dirs+files:
            p=pathlib.Path(base)/name
            rel=p.relative_to(root).as_posix()
            if rel in VOLATILE: continue
            st=os.lstat(p)
            if stat.S_ISLNK(st.st_mode):
                tgt=os.readlink(p)
                # Toolchains are mounted below /opt/klab-toolchain at build time.
                # An absolute symlink would therefore resolve against the buildenv
                # root rather than this toolchain root, creating a host/buildenv
                # escape even when the same path exists inside the artifact. Bound
                # toolchains must be relocatable, so reject absolute links.
                if os.path.isabs(tgt):
                    die(f'absolute symlink is not relocatable in toolchain: {rel} -> {tgt}')
                resolved=(p.parent/tgt).resolve(strict=False)
                try: resolved.relative_to(root)
                except ValueError: die(f'symlink escapes toolchain root: {rel} -> {tgt}')
                if not resolved.exists(): die(f'dangling toolchain symlink: {rel} -> {tgt}')
            elif not (stat.S_ISDIR(st.st_mode) or stat.S_ISREG(st.st_mode)):
                die(f'unsupported special file in toolchain root: {rel}')


def tree_digest(root):
    root=pathlib.Path(root).resolve(); h=hashlib.sha256()
    def add(v): h.update(v.encode('utf-8','surrogateescape')+b'\0')
    for base, dirs, files in os.walk(root,topdown=True,followlinks=False):
        dirs.sort(); files.sort()
        for name in dirs+files:
            p=pathlib.Path(base)/name; rel=p.relative_to(root).as_posix()
            if rel in VOLATILE: continue
            st=os.lstat(p); mode=stat.S_IMODE(st.st_mode)
            if stat.S_ISDIR(st.st_mode): typ,payload='d',''
            elif stat.S_ISREG(st.st_mode): typ,payload='f',sha_file(p)
            elif stat.S_ISLNK(st.st_mode): typ,payload='l',os.readlink(p)
            else: die(f'unsupported special file in toolchain root: {rel}')
            add(typ); add(rel); add(f'{mode:o}'); add(payload)
    return h.hexdigest()


def run1(argv):
    try:
        r=subprocess.run(argv,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,check=True,env={'LC_ALL':'C','LANG':'C','PATH':'/usr/bin:/bin'})
    except (OSError,subprocess.CalledProcessError) as e:
        die(f'compiler probe failed: {argv[0]} {argv[1:]!r}')
    return r.stdout.strip().splitlines()[0] if r.stdout.strip() else ''


def compiler_info(root, cc_rel):
    root=pathlib.Path(root).resolve(); cc_rel=clean_rel(cc_rel,'compiler path')
    cc=real_inside(root,cc_rel,'compiler')
    if not os.access(cc,os.X_OK): die(f'compiler is not executable: {cc_rel}')
    base=pathlib.Path(cc_rel).name
    if 'gcc' not in base and base not in ('cc','gcc'):
        die(f'toolchain boundary v1 supports GCC only, got {base}')
    version=run1([str(cc),'-dumpfullversion','-dumpversion']) or run1([str(cc),'-dumpversion'])
    target=run1([str(cc),'-dumpmachine']) or 'unknown'
    return cc,version,target


def candidate_program(root, cc, cc_rel, name):
    root=pathlib.Path(root).resolve(); cc_rel=pathlib.PurePosixPath(cc_rel)
    # GCC knows the location of cc1/as/ld on most real toolchains. Accept only
    # paths that resolve inside the bound root; never resolve through host PATH.
    probe=run1([str(cc),f'-print-prog-name={name}'])
    candidates=[]
    if probe and probe != name:
        pp=pathlib.Path(probe)
        if not pp.is_absolute(): pp=pathlib.Path(cc).parent/probe
        candidates.append(pp)
    bindir=root/pathlib.Path(cc_rel).parent
    base=pathlib.Path(cc_rel).name
    prefix=''
    if base.endswith('-gcc'): prefix=base[:-3]  # includes trailing '-'
    if name=='cc1':
        # cc1 is normally outside bin; only use GCC's explicit answer.
        pass
    else:
        if prefix: candidates.append(bindir/f'{prefix}{name}')
        candidates.append(bindir/name)
    seen=set()
    for p in candidates:
        sp=str(p)
        if sp in seen: continue
        seen.add(sp)
        try: rp=real_inside(root,p,f'{name} helper')
        except SystemExit: continue
        if rp.is_file() and os.access(rp,os.X_OK): return rp.relative_to(root).as_posix()
    die(f'bound toolchain lacks in-root required helper: {name}')


def inspect(root, cc_rel):
    root=pathlib.Path(root).resolve(); validate_tree(root)
    cc,version,target=compiler_info(root,cc_rel)
    programs={'cc':pathlib.Path(cc).relative_to(root).as_posix()}
    for n in REQUIRED: programs[n]=candidate_program(root,cc,cc_rel,n)
    return {
      'format':FORMAT,'format_version':VERSION,'family':'gcc','version':version,
      'target':target,'cc_relpath':programs['cc'],'programs':programs,
      'tree_sha256':tree_digest(root)
    }


def load_meta(root):
    p=pathlib.Path(root)/META
    if not p.is_file(): return None
    try: m=json.loads(p.read_text())
    except Exception as e: die(f'invalid {META}: {e}')
    if m.get('format')!=FORMAT or m.get('format_version')!=VERSION: die('unsupported toolchain boundary metadata')
    return m


def cmd_seal(a):
    root=pathlib.Path(a.root).resolve(); info=inspect(root,a.cc)
    p=root/META; p.write_text(json.dumps(info,indent=2,sort_keys=True)+'\n')
    if a.json: print(json.dumps(info,sort_keys=True,separators=(',',':')))
    else: print(info['tree_sha256'])


def cmd_verify(a):
    root=pathlib.Path(a.root).resolve(); meta=load_meta(root)
    cc=a.cc or (meta or {}).get('cc_relpath')
    if not cc: die('compiler path is required when toolchain has no boundary metadata')
    info=inspect(root,cc)
    expected=a.tree_sha256 or (meta or {}).get('tree_sha256')
    if not expected: die('no expected toolchain tree digest; seal/import with current KLab first')
    if info['tree_sha256']!=expected: die(f'toolchain tree digest mismatch: expected {expected}, got {info["tree_sha256"]}')
    # Metadata itself must agree with what is actually installed. External args,
    # when supplied by the target manifest, take precedence over stored metadata.
    family=a.family or (meta or {}).get('family')
    version=a.version or (meta or {}).get('version')
    target=a.target or (meta or {}).get('target')
    if family and family!='gcc': die(f'unsupported compiler family for boundary v1: {family}')
    if version and info['version']!=version: die(f'compiler version mismatch: expected {version}, got {info["version"]}')
    if target and target!='unknown' and info['target']!=target: die(f'compiler target mismatch: expected {target}, got {info["target"]}')
    if meta:
        for n,rel in (meta.get('programs') or {}).items():
            if n in info['programs'] and info['programs'][n]!=rel: die(f'toolchain helper path changed for {n}: {rel} -> {info["programs"][n]}')
    if a.json: print(json.dumps(info,sort_keys=True,separators=(',',':')))
    else: print(info['tree_sha256'])


def main():
    ap=argparse.ArgumentParser(); sp=ap.add_subparsers(dest='cmd',required=True)
    p=sp.add_parser('seal'); p.add_argument('--root',required=True); p.add_argument('--cc',required=True); p.add_argument('--json',action='store_true'); p.set_defaults(func=cmd_seal)
    p=sp.add_parser('verify'); p.add_argument('--root',required=True); p.add_argument('--cc'); p.add_argument('--tree-sha256'); p.add_argument('--family'); p.add_argument('--version'); p.add_argument('--target'); p.add_argument('--json',action='store_true'); p.set_defaults(func=cmd_verify)
    a=ap.parse_args(); a.func(a)
if __name__=='__main__': main()
