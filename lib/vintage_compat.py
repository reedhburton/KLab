#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, pathlib, re, subprocess, sys

# Static compatibility preflight for modules built for historical kernels.
# It deliberately distinguishes authoritative source-backed answers from
# conservative vintage hazards. Distro kernels can backport relocation support.

ARCH = {
    'x86_64': ('x86', 'R_X86_64_'),
    'amd64': ('x86', 'R_X86_64_'),
    'i386': ('x86', 'R_386_'),
    'i686': ('x86', 'R_386_'),
    'aarch64': ('arm64', 'R_AARCH64_'),
    'arm64': ('arm64', 'R_AARCH64_'),
    'armv7': ('arm', 'R_ARM_'),
    'armv7l': ('arm', 'R_ARM_'),
    'armhf': ('arm', 'R_ARM_'),
}

def die(msg, rc=1):
    print(f'klab-vintage: ERROR: {msg}', file=sys.stderr)
    raise SystemExit(rc)

def readelf_relocs(module: pathlib.Path):
    try:
        p=subprocess.run(['readelf','-rW',str(module)],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True)
    except (OSError,subprocess.CalledProcessError) as e:
        die(f'cannot inspect module relocations: {module}')
    rel=[]
    for line in p.stdout.splitlines():
        m=re.search(r'\b(R_[A-Z0-9_]+)\b', line)
        if m: rel.append(m.group(1))
    return sorted(set(rel))

def kernel_version(krel):
    m=re.match(r'^(\d+)\.(\d+)(?:\.(\d+))?',krel or '')
    return tuple(int(x or 0) for x in m.groups()) if m else None

def source_reloc_tokens(source: pathlib.Path, karch: str, prefix: str):
    # Module relocation handling moved around over time. Scan the architecture
    # tree rather than one hard-coded filename, but keep the scope narrow.
    base=source/'arch'/karch
    if not base.is_dir(): return None, []
    files=[]; tokens=set()
    for p in base.rglob('*'):
        if not p.is_file(): continue
        rel=p.relative_to(base).as_posix()
        if ('module' not in p.name.lower() and 'reloc' not in p.name.lower() and 'kexec' not in p.name.lower()):
            continue
        if p.suffix not in ('.c','.h','.S',''):
            continue
        try: text=p.read_text(errors='ignore')
        except OSError: continue
        found=set(re.findall(r'\b'+re.escape(prefix)+r'[A-Z0-9_]+\b',text))
        if found:
            tokens.update(found); files.append(rel)
    return tokens, files

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--module',required=True)
    ap.add_argument('--arch',required=True)
    ap.add_argument('--kernel-release',required=True)
    ap.add_argument('--kernel-source')
    ap.add_argument('--binutils-version',default='')
    ap.add_argument('--strict-vintage',action='store_true')
    ap.add_argument('--json',action='store_true')
    a=ap.parse_args()
    mod=pathlib.Path(a.module)
    if not mod.is_file(): die(f'module not found: {mod}')
    if a.arch not in ARCH: die(f'unsupported architecture for vintage validation: {a.arch}')
    karch,prefix=ARCH[a.arch]
    relocs=readelf_relocs(mod)
    arch_relocs=sorted(x for x in relocs if x.startswith(prefix))
    result={'kernel_release':a.kernel_release,'arch':a.arch,'module':str(mod),'relocations':arch_relocs,
            'authority':'heuristic','status':'pass','hazards':[],'source_files':[]}

    if a.kernel_source:
        toks,files=source_reloc_tokens(pathlib.Path(a.kernel_source),karch,prefix)
        if toks is None:
            die(f'kernel source lacks arch/{karch}: {a.kernel_source}')
        result['authority']='kernel-source'
        result['source_files']=files
        # Do not reject ordinary absolute/data relocations merely because a
        # source scan missed a token. Restrict authoritative rejection to
        # relocation types with known loader compatibility transitions.
        hazards=[]
        if a.arch in ('x86_64','amd64') and 'R_X86_64_PLT32' in arch_relocs and 'R_X86_64_PLT32' not in toks:
            hazards.append({'relocation':'R_X86_64_PLT32','reason':'kernel source module relocation handlers do not advertise PLT32 support'})
        if a.arch in ('i386','i686') and 'R_386_PLT32' in arch_relocs and 'R_386_PLT32' not in toks:
            hazards.append({'relocation':'R_386_PLT32','reason':'kernel source module relocation handlers do not advertise PLT32 support'})
        result['hazards']=hazards
        if hazards: result['status']='fail'
    else:
        kv=kernel_version(a.kernel_release)
        bv=kernel_version(a.binutils_version)
        # PLT32 emission for x86-64 branches appeared in binutils master in
        # Feb 2018 and shipped in the 2.31 generation. Older distro kernels may
        # or may not carry the corresponding Linux backport, so without exact
        # source/runtime evidence this is intentionally "unproven", not fail.
        if a.arch in ('x86_64','amd64') and 'R_X86_64_PLT32' in arch_relocs:
            old_kernel = kv is not None and kv < (4,16,0)
            new_as = bv is None or bv >= (2,31,0)
            if old_kernel and new_as:
                result['hazards'].append({'relocation':'R_X86_64_PLT32','reason':'vintage x86-64 kernel plus PLT32-producing assembler requires exact source or runtime proof; stable/distro backports vary'})
        if a.arch in ('i386','i686') and 'R_386_PLT32' in arch_relocs:
            old_kernel = kv is not None and kv < (5,12,0)
            if old_kernel:
                result['hazards'].append({'relocation':'R_386_PLT32','reason':'vintage i386 kernel plus PLT32 requires exact source or runtime proof; backports vary'})
        if result['hazards']: result['status']='unproven'

    if a.json:
        print(json.dumps(result,sort_keys=True,separators=(',',':')))
    else:
        print(f"KLAB_VINTAGE_STATUS={result['status']}")
        print(f"KLAB_VINTAGE_AUTHORITY={result['authority']}")
        print('KLAB_VINTAGE_RELOCS='+','.join(result['relocations']))
        for h in result['hazards']:
            print(f"KLAB_VINTAGE_HAZARD={h['relocation']}: {h['reason']}")
    if result['status']=='fail': raise SystemExit(1)
    if result['status']=='unproven' and a.strict_vintage: raise SystemExit(2)

if __name__=='__main__': main()
