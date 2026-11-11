#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, os, pathlib, shutil, stat, subprocess, sys, tarfile, tempfile, time

FORMAT='kernel-lab-buildenv'
VERSION=4
SUPPORTED_VERSIONS={1,2,3,4}
EXPECTED_OUTER_V1={'FORMAT_VERSION','manifest.json','SHA256SUMS','payload/root.tar.zst','spec/package-manifest.txt'}
EXPECTED_OUTER_V2=EXPECTED_OUTER_V1|{'spec/installed-packages.tsv'}
EXPECTED_OUTER_V4=EXPECTED_OUTER_V2|{
    'payload/dependency-archives.tar.zst',
    'spec/dependency-archives.sha256',
    'spec/dependency-provenance.json',
}

def expected_outer(version):
    if version>=4: return EXPECTED_OUTER_V4
    return EXPECTED_OUTER_V2 if version>=2 else EXPECTED_OUTER_V1

def spec_keys(version):
    keys=['format','format_version','artifact_type','provider','release','kernel_release','target_arch','exec_arch','provider_image','recipe_version','build_dir_rel','source_dir_rel','package_manifest_sha256','root_tree_sha256','compiler_contract','toolchain_tree_sha256','toolchain_family','toolchain_version','toolchain_target','toolchain_cc_relpath']
    if version>=2: keys.append('installed_inventory_sha256')
    if version>=3: keys.append('distro_toolchain_id')
    if version>=4: keys.extend(('dependency_archive_manifest_sha256','dependency_provenance_sha256','dependency_archive_tree_sha256'))
    return keys

def die(msg):
    raise SystemExit(f'klab-buildenv: ERROR: {msg}')

def sha_file(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(1024*1024), b''): h.update(b)
    return h.hexdigest()

def clean_rel(s, name='path'):
    if not s: return ''
    p=pathlib.PurePosixPath(s)
    if p.is_absolute() or '..' in p.parts: die(f'unsafe {name}: {s}')
    return str(p)

def tree_digest(root):
    root=pathlib.Path(root)
    h=hashlib.sha256()
    def add(x): h.update(x.encode('utf-8','surrogateescape')+b'\0')
    for base, dirs, files in os.walk(root, topdown=True, followlinks=False):
        dirs.sort(); files.sort()
        names=dirs+files
        for name in names:
            p=pathlib.Path(base)/name
            rel=p.relative_to(root).as_posix()
            st=os.lstat(p); mode=stat.S_IMODE(st.st_mode)
            if stat.S_ISDIR(st.st_mode): typ='d'; payload=''
            elif stat.S_ISREG(st.st_mode): typ='f'; payload=sha_file(p)
            elif stat.S_ISLNK(st.st_mode): typ='l'; payload=os.readlink(p)
            else: die(f'unsupported special file in buildenv root: {rel}')
            add(typ); add(rel); add(f'{mode:o}'); add(payload)
    return h.hexdigest()

def validate_tree(root, allow_abs_symlinks=True):
    # A buildenv root is a filesystem image, not part of the host namespace.
    # Therefore an absolute link such as /bin/mt -> /etc/alternatives/mt is
    # rooted at the buildenv's / when the image is mounted under bwrap.  Do
    # not feed such links to pathlib.resolve(), which would incorrectly
    # interpret them in the host filesystem.  Relative links are checked
    # lexically and may walk upward only as far as the buildenv root.
    root=pathlib.Path(root).resolve()
    for base, dirs, files in os.walk(root, topdown=True, followlinks=False):
        for name in dirs+files:
            p=pathlib.Path(base)/name
            rel=p.relative_to(root).as_posix(); st=os.lstat(p)
            if stat.S_ISLNK(st.st_mode):
                tgt=os.readlink(p)
                if os.path.isabs(tgt):
                    if not allow_abs_symlinks: die(f'absolute symlink not allowed: {rel} -> {tgt}')
                    # Absolute links are sandbox-root-relative by definition.
                    continue
                stack=list(pathlib.PurePosixPath(rel).parent.parts)
                for part in pathlib.PurePosixPath(tgt).parts:
                    if part in ('', '.'):
                        continue
                    if part == '..':
                        if not stack:
                            die(f'symlink escapes buildenv root: {rel} -> {tgt}')
                        stack.pop()
                    else:
                        stack.append(part)
            elif not (stat.S_ISDIR(st.st_mode) or stat.S_ISREG(st.st_mode)):
                die(f'unsupported special file in buildenv root: {rel}')

def validate_host_tool_owners(root, inventory_file):
    """Bind the distro-native kbuild baseline to the realized package inventory."""
    root=pathlib.Path(root)
    owners=root/'var/lib/klab/host-tool-owners.tsv'
    if not owners.is_file() or not owners.read_text().strip():
        die('host-tool ownership inventory missing or empty')
    packages=set()
    for lineno,line in enumerate(pathlib.Path(inventory_file).read_text().splitlines(),1):
        if not line.strip(): continue
        cols=line.split('\t')
        if len(cols)!=3 or not all(cols): die(f'malformed installed package inventory line {lineno}')
        packages.add(cols[0])
    seen_tools=set(); seen_paths={}
    for lineno,line in enumerate(owners.read_text().splitlines(),1):
        cols=line.split('\t')
        if len(cols)!=3 or not all(cols): die(f'malformed host-tool ownership line {lineno}')
        tool,path,owner=cols
        if tool in seen_tools: die(f'duplicate host-tool ownership entry: {tool}')
        if path in seen_paths and seen_paths[path] != owner: die(f'conflicting host-tool executable owners: {path}')
        if not path.startswith('/') or '..' in pathlib.PurePosixPath(path).parts:
            die(f'unsafe host-tool executable path: {path}')
        # Resolve links in the image namespace: absolute symlink targets are
        # rooted at buildenv /, never at the audit host's /.
        rel=pathlib.PurePosixPath(path.lstrip('/')); hops=0
        while True:
            hp=root/str(rel)
            try: st=os.lstat(hp)
            except FileNotFoundError: die(f'host-tool executable missing from buildenv root: {path}')
            if not stat.S_ISLNK(st.st_mode): break
            hops+=1
            if hops>40: die(f'host-tool symlink loop: {path}')
            tgt=os.readlink(hp)
            if os.path.isabs(tgt): rel=pathlib.PurePosixPath(tgt.lstrip('/'))
            else: rel=pathlib.PurePosixPath(os.path.normpath(str(rel.parent/tgt)))
            if '..' in rel.parts: die(f'host-tool symlink escapes buildenv root: {path}')
        if not stat.S_ISREG(st.st_mode) or not (stat.S_IMODE(st.st_mode)&0o111): die(f'host-tool executable is not executable: {path}')
        if owner not in packages: die(f'host-tool owner absent from installed package inventory: {owner} ({tool})')
        seen_tools.add(tool); seen_paths[path]=owner
    required={'/bin/sh','/usr/bin/make','awk','sed','grep','find','xargs','basename','dirname','tr','cut','sort','head','mkdir','rm','cp','mv','ln','cat'}
    missing=required-seen_tools
    if missing: die('host-tool ownership inventory missing baseline entries: '+','.join(sorted(missing)))

def validate_dependency_closure(root, manifest_file, provenance_file, provider, release, installed_inventory_file=None):
    import re
    root=pathlib.Path(root).resolve(); manifest_file=pathlib.Path(manifest_file); provenance_file=pathlib.Path(provenance_file)
    if not root.is_dir(): die('dependency archive directory does not exist')
    rows={}
    for lineno,raw in enumerate(manifest_file.read_text().splitlines(),1):
        if not raw.strip(): continue
        m=re.fullmatch(r'([0-9a-fA-F]{64})\s+[ *]?(.+)',raw.strip())
        if not m: die(f'malformed dependency archive manifest line {lineno}')
        digest,name=m.group(1).lower(),m.group(2)
        if name in rows or '/' in name or name in ('.','..'): die(f'unsafe or duplicate dependency archive name: {name}')
        if pathlib.Path(name).suffix not in ('.deb','.rpm','.apk'): die(f'unsupported dependency archive type: {name}')
        rows[name]=digest
    entries=list(root.iterdir())
    bad_dirs=[x.name for x in entries if x.is_dir() and x.name!='repository-metadata']
    if bad_dirs: die(f'unexpected dependency closure directories: {sorted(bad_dirs)}')
    files={x.name for x in entries if x.is_file()}
    allowed=set(rows)|{'PACKAGES.sha256'}
    if files-allowed: die(f'unmanifested dependency closure files: {sorted(files-allowed)}')
    actual={x for x in files if pathlib.Path(x).suffix in ('.deb','.rpm','.apk')}
    if set(rows)!=actual: die(f'dependency archive manifest set mismatch: manifest={sorted(rows)} actual={sorted(actual)}')
    for name,digest in rows.items():
        if sha_file(root/name)!=digest: die(f'dependency archive checksum mismatch: {name}')
    try: prov=json.loads(provenance_file.read_text())
    except (OSError,json.JSONDecodeError) as e: die(f'invalid dependency provenance: {e}')
    if prov.get('schema')!='klab-buildenv-dependency-provenance-v1': die('unsupported dependency provenance schema')
    if prov.get('provider')!=provider or str(prov.get('release'))!=str(release): die('dependency provenance provider/release mismatch')
    repos=prov.get('repositories')
    if not isinstance(repos,list) or not repos: die('dependency provenance has no repository snapshots')
    for repo in repos:
        if not isinstance(repo,dict) or not repo.get('url') or not re.fullmatch(r'[0-9a-f]{64}',str(repo.get('metadata_sha256',''))):
            die('malformed dependency repository snapshot')
        metadata_file=repo.get('metadata_file')
        if not isinstance(metadata_file,str) or pathlib.PurePosixPath(metadata_file).is_absolute() or '..' in pathlib.PurePosixPath(metadata_file).parts:
            die('unsafe dependency repository metadata path')
        metadata_path=root/metadata_file
        if not metadata_path.is_file() or sha_file(metadata_path)!=repo['metadata_sha256']:
            die(f'dependency repository metadata mismatch: {metadata_file}')
    packages=prov.get('packages')
    if not isinstance(packages,list): die('dependency provenance packages must be a list')
    mapped={}; mapped_identities=set()
    for row in packages:
        if not isinstance(row,dict): die('malformed dependency provenance package row')
        name=row.get('file'); digest=str(row.get('sha256','')).lower()
        if name not in rows or digest!=rows.get(name) or name in mapped and mapped[name]!=digest: die(f'dependency provenance package mismatch: {name}')
        if not all(row.get(k) for k in ('name','version','arch')): die(f'incomplete dependency package identity: {name}')
        identity=(str(row['name']),str(row['version']),str(row['arch']))
        if identity in mapped_identities: die(f'duplicate dependency package identity: {identity}')
        mapped_identities.add(identity); mapped[name]=digest
    if set(mapped)!=set(rows): die('dependency provenance does not cover the exact archive set')
    if installed_inventory_file is not None:
        installed=set()
        for lineno,line in enumerate(pathlib.Path(installed_inventory_file).read_text().splitlines(),1):
            if not line.strip(): continue
            cols=line.split('\t')
            if len(cols)!=3 or not all(cols): die(f'malformed installed package inventory line {lineno}')
            installed.add(tuple(cols))
        archived={(str(row['name']),str(row['version']),str(row['arch'])) for row in packages}
        if archived!=installed:
            missing=sorted(installed-archived); extra=sorted(archived-installed)
            die(f'dependency archive closure does not equal installed inventory: missing={missing} extra={extra}')
    return rows,prov


def canonical_spec(args, root_digest, pkg_sha, inventory_sha, version, dependency_manifest_sha='', dependency_provenance_sha='', dependency_tree_sha=''):
    spec={
      'format':FORMAT,'format_version':version,'artifact_type':'buildenv',
      'provider':args.provider,'release':args.release,'kernel_release':args.kernel_release,
      'target_arch':args.target_arch,'exec_arch':args.exec_arch,
      'provider_image':args.provider_image or '', 'recipe_version':args.recipe_version,
      'build_dir_rel':clean_rel(args.build_dir,'build directory'),
      'source_dir_rel':clean_rel(args.source_dir,'source directory') if args.source_dir else '',
      'package_manifest_sha256':pkg_sha,'installed_inventory_sha256':inventory_sha,'root_tree_sha256':root_digest,
      'compiler_contract':args.compiler_contract,
      'toolchain_tree_sha256':args.toolchain_tree_sha256 or '',
      'toolchain_family':args.toolchain_family or '',
      'toolchain_version':args.toolchain_version or '',
      'toolchain_target':args.toolchain_target or '',
      'toolchain_cc_relpath':clean_rel(args.toolchain_cc_relpath,'toolchain compiler path') if args.toolchain_cc_relpath else '',
      'distro_toolchain_id':args.distro_toolchain_id or ''
    }
    if version>=4:
        spec.update({
          'dependency_archive_manifest_sha256':dependency_manifest_sha,
          'dependency_provenance_sha256':dependency_provenance_sha,
          'dependency_archive_tree_sha256':dependency_tree_sha,
        })
    return spec

def canonical_json(o): return json.dumps(o,sort_keys=True,separators=(',',':')).encode()

def artifact_id(spec): return hashlib.sha256(canonical_json(spec)).hexdigest()

def write_canonical_root_tar(root, out):
    cmd=['tar','-C',str(root),'--sort=name','--mtime=@0','--owner=0','--group=0','--numeric-owner',
         '--pax-option=delete=atime,delete=ctime','-cf','-','.']
    with open(out,'wb') as f:
        p1=subprocess.Popen(cmd,stdout=subprocess.PIPE)
        p2=subprocess.Popen(['zstd','-q','-T0','-10','-c'],stdin=p1.stdout,stdout=f)
        p1.stdout.close(); r2=p2.wait(); r1=p1.wait()
        if r1 or r2: die('failed to create canonical root archive')

def outer_members(file):
    p=subprocess.Popen(['zstd','-dc',str(file)],stdout=subprocess.PIPE)
    completed=False
    try:
        with tarfile.open(fileobj=p.stdout,mode='r|') as tf:
            for m in tf:
                yield m
        completed=True
    finally:
        if p.stdout: p.stdout.close()
        rc=p.wait()
        # If the consumer rejected an entry early, zstd can receive SIGPIPE.
        # Do not mask the real validation error with a generator-finalizer error.
        if completed and rc: die('could not read compressed artifact')

def safe_tar_members(file, expected=None, payload=False):
    # Hardlinks are normal in Debian/Ubuntu roots (for example bzcat/bzip2).
    # Rejecting all of them makes valid captured roots impossible to package.
    # Instead validate the archive namespace first, then require every hardlink
    # to resolve, entirely inside that namespace, to a regular-file member.
    members=[]
    for m in outer_members(file):
        n=m.name
        while n.startswith('./'): n=n[2:]
        if not n: continue
        pp=pathlib.PurePosixPath(n)
        if pp.is_absolute() or '..' in pp.parts: die(f'unsafe archive path: {m.name}')
        if m.isdev() or m.isfifo(): die(f'special archive entry rejected: {n}')
        members.append((n.rstrip('/'), m))

    by_name={}
    for n,m in members:
        if n in by_name: die(f'duplicate archive entry rejected: {n}')
        by_name[n]=m

    def clean_hardlink_target(src, target):
        t=target
        while t.startswith('./'): t=t[2:]
        pp=pathlib.PurePosixPath(t)
        if not t or pp.is_absolute() or '..' in pp.parts:
            die(f'unsafe hardlink target: {src} -> {target}')
        return str(pp).rstrip('/')

    def hardlink_resolves_to_regular(src):
        seen_links=set()
        cur=src
        while True:
            if cur in seen_links: die(f'hardlink cycle rejected: {src}')
            seen_links.add(cur)
            m=by_name.get(cur)
            if m is None: die(f'hardlink target missing from archive: {src} -> {cur}')
            if m.isreg(): return
            if not m.islnk(): die(f'hardlink target is not a regular file: {src} -> {cur}')
            cur=clean_hardlink_target(cur, m.linkname)

    seen=set()
    for n,m in members:
        if m.islnk():
            target=clean_hardlink_target(n, m.linkname)
            hardlink_resolves_to_regular(target)
        if payload and m.issym():
            tgt=m.linkname
            if not os.path.isabs(tgt):
                resolved=pathlib.PurePosixPath(n).parent.joinpath(tgt)
                # lexical normalize without following FS
                stack=[]
                for part in resolved.parts:
                    if part in ('','.'): continue
                    if part=='..':
                        if not stack: die(f'symlink escapes payload root: {n} -> {tgt}')
                        stack.pop()
                    else: stack.append(part)
            # absolute symlinks are valid inside the sandboxed build root.
        seen.add(n)
    if expected is not None:
        files={x for x in seen if x in expected}
        missing=expected-files
        extra={x for x in seen if x not in expected and x not in ('payload','spec')}
        if missing: die(f'artifact missing required entries: {sorted(missing)}')
        if extra: die(f'artifact contains unexpected outer entries: {sorted(extra)}')

def extract_zst_tar(file, dest):
    subprocess.run(['tar','--zstd','-xf',str(file),'-C',str(dest),'--no-same-owner'],check=True)

def parse_sums(p, version):
    rows={}
    for line in pathlib.Path(p).read_text().splitlines():
        if not line.strip(): continue
        parts=line.split(None,1)
        if len(parts)!=2: die('malformed SHA256SUMS')
        sha,name=parts; name=name.lstrip('*').strip()
        if name in rows: die(f'duplicate checksum entry: {name}')
        clean_rel(name,'checksum path'); rows[name]=sha
    expected=expected_outer(version)-{'SHA256SUMS'}
    if set(rows)!=expected: die(f'checksum manifest must cover exactly {sorted(expected)}')
    return rows

def verify_extracted(stage, deep=True):
    stage=pathlib.Path(stage)
    try: version=int((stage/'FORMAT_VERSION').read_text().strip())
    except ValueError: die('invalid buildenv format version')
    if version not in SUPPORTED_VERSIONS: die('unsupported buildenv format version')
    sums=parse_sums(stage/'SHA256SUMS',version)
    for rel,sha in sums.items():
        p=stage/rel
        if not p.is_file(): die(f'checksummed file missing: {rel}')
        if sha_file(p)!=sha: die(f'checksum mismatch: {rel}')
    m=json.loads((stage/'manifest.json').read_text())
    if m.get('format')!=FORMAT or m.get('format_version')!=version or m.get('artifact_type')!='buildenv': die('invalid buildenv manifest')
    am=m.get('architecture_model') or {}
    if am:
        if am.get('schema')!='klab-arch-plan-v1': die('unsupported buildenv architecture model')
        if am.get('target_arch')!=m.get('target_arch'): die('buildenv architecture target mismatch')
        if am.get('build_arch')!=m.get('exec_arch') or am.get('toolchain_exec_arch')!=m.get('exec_arch'): die('buildenv architecture execution mismatch')
        if am.get('toolchain_target_arch')!=m.get('target_arch') or am.get('guest_arch')!=m.get('target_arch'): die('buildenv architecture target-role mismatch')
    spec={k:m.get(k,'') for k in spec_keys(version)}
    if artifact_id(spec)!=m.get('id'): die('buildenv content/spec ID mismatch')
    if sha_file(stage/'spec/package-manifest.txt')!=m.get('package_manifest_sha256'): die('package manifest hash mismatch')
    if version>=2 and sha_file(stage/'spec/installed-packages.tsv')!=m.get('installed_inventory_sha256'): die('installed package inventory hash mismatch')
    if version>=4:
        if sha_file(stage/'spec/dependency-archives.sha256')!=m.get('dependency_archive_manifest_sha256'): die('dependency archive manifest hash mismatch')
        if sha_file(stage/'spec/dependency-provenance.json')!=m.get('dependency_provenance_sha256'): die('dependency provenance hash mismatch')
        safe_tar_members(stage/'payload/dependency-archives.tar.zst', payload=True)
    if sha_file(stage/'payload/root.tar.zst')!=m.get('root_archive_sha256'): die('root archive hash mismatch')
    safe_tar_members(stage/'payload/root.tar.zst', payload=True)
    if deep:
        tmp=pathlib.Path(tempfile.mkdtemp(prefix='klab-buildenv-deep-'))
        try:
            extract_zst_tar(stage/'payload/root.tar.zst',tmp)
            validate_tree(tmp)
            if tree_digest(tmp)!=m.get('root_tree_sha256'): die('root tree digest mismatch')
            if version>=3 and m.get('compiler_contract')=='distro-native-v1': validate_host_tool_owners(tmp, stage/'spec/installed-packages.tsv')
            if version>=4:
                deps=tmp/'__klab_dependency_archives'; deps.mkdir()
                extract_zst_tar(stage/'payload/dependency-archives.tar.zst',deps)
                validate_dependency_closure(deps,stage/'spec/dependency-archives.sha256',stage/'spec/dependency-provenance.json',m['provider'],m['release'],stage/'spec/installed-packages.tsv')
                if tree_digest(deps)!=m.get('dependency_archive_tree_sha256'): die('dependency archive tree digest mismatch')
            b=tmp/m['build_dir_rel']
            if not b.is_dir() or not (b/'Makefile').is_file(): die('build tree missing Makefile')
            if not (b/'scripts/Makefile.build').is_file(): die('build tree missing scripts/Makefile.build')
        finally: shutil.rmtree(tmp,ignore_errors=True)
    return m

def verify_archive(file, deep=True):
    file=pathlib.Path(file)
    if not file.is_file(): die(f'artifact not found: {file}')
    safe_tar_members(file)
    tmp=pathlib.Path(tempfile.mkdtemp(prefix='klab-buildenv-'))
    try:
        extract_zst_tar(file,tmp)
        try: version=int((tmp/'FORMAT_VERSION').read_text().strip())
        except (OSError,ValueError): die('invalid buildenv format version')
        if version not in SUPPORTED_VERSIONS: die('unsupported buildenv format version')
        safe_tar_members(file, expected_outer(version))
        return verify_extracted(tmp,deep)
    finally: shutil.rmtree(tmp,ignore_errors=True)

def cmd_create(a):
    root=pathlib.Path(a.root).resolve(); pkg=pathlib.Path(a.package_manifest).resolve(); inventory=pathlib.Path(a.installed_inventory).resolve()
    has_dependency_closure=bool(a.dependency_archives or a.dependency_provenance)
    if bool(a.dependency_archives)!=bool(a.dependency_provenance): die('dependency archives and dependency provenance must be supplied together')
    version=4 if has_dependency_closure else 3
    dependency_root=pathlib.Path(a.dependency_archives).resolve() if has_dependency_closure else None
    dependency_manifest=(dependency_root/'PACKAGES.sha256') if has_dependency_closure else None
    dependency_provenance=pathlib.Path(a.dependency_provenance).resolve() if has_dependency_closure else None
    if not root.is_dir(): die('root directory does not exist')
    if not pkg.is_file(): die('package manifest does not exist')
    if not inventory.is_file() or not inventory.read_text().strip(): die('installed package inventory does not exist or is empty')
    import re
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', (a.provider_image or '').lower()): die('provider image must be a canonical sha256 content ID')
    a.provider_image=(a.provider_image or '').lower()
    validate_tree(root)
    if a.compiler_contract == 'distro-native-v1': validate_host_tool_owners(root, inventory)
    build=root/clean_rel(a.build_dir,'build directory')
    if not build.is_dir() or not (build/'Makefile').is_file() or not (build/'scripts/Makefile.build').is_file(): die('root does not contain a usable kernel build tree')
    import re
    if a.compiler_contract == 'distro-native-v1':
        if not re.fullmatch(r'[0-9a-f]{64}', a.distro_toolchain_id or ''): die('distro-native buildenv requires a sha256 distro-toolchain ID')
        if any((a.toolchain_tree_sha256,a.toolchain_family,a.toolchain_version,a.toolchain_target,a.toolchain_cc_relpath)): die('distro-native buildenv must not pin a relocatable toolchain')
    elif a.compiler_contract == 'gcc-v1':
        if a.distro_toolchain_id: die('gcc-v1 buildenv must not pin a distro-toolchain ID')
    else: die(f'unsupported compiler contract: {a.compiler_contract}')
    dep_manifest_sha=dep_provenance_sha=dep_tree_sha=''
    if has_dependency_closure:
        if not dependency_manifest.is_file(): die('dependency archive directory has no PACKAGES.sha256')
        validate_dependency_closure(dependency_root,dependency_manifest,dependency_provenance,a.provider,a.release,inventory)
        dep_manifest_sha=sha_file(dependency_manifest); dep_provenance_sha=sha_file(dependency_provenance); dep_tree_sha=tree_digest(dependency_root)
    rd=tree_digest(root); ps=sha_file(pkg); ins=sha_file(inventory)
    spec=canonical_spec(a,rd,ps,ins,version,dep_manifest_sha,dep_provenance_sha,dep_tree_sha); aid=artifact_id(spec)
    stage=pathlib.Path(tempfile.mkdtemp(prefix='klab-buildenv-create-'))
    try:
        (stage/'payload').mkdir(); (stage/'spec').mkdir()
        (stage/'FORMAT_VERSION').write_text(str(version)+'\n')
        shutil.copy2(pkg,stage/'spec/package-manifest.txt')
        shutil.copy2(inventory,stage/'spec/installed-packages.tsv')
        if version>=4:
            shutil.copy2(dependency_manifest,stage/'spec/dependency-archives.sha256')
            shutil.copy2(dependency_provenance,stage/'spec/dependency-provenance.json')
            write_canonical_root_tar(dependency_root,stage/'payload/dependency-archives.tar.zst')
        write_canonical_root_tar(root,stage/'payload/root.tar.zst')
        m=dict(spec); m.update({'id':aid,'created_at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'root_archive_sha256':sha_file(stage/'payload/root.tar.zst')})
        m['architecture_model']={
            'schema':'klab-arch-plan-v1','model_version':1,
            'target_arch':a.target_arch,'build_arch':a.exec_arch,
            'toolchain_exec_arch':a.exec_arch,'toolchain_target_arch':a.target_arch,
            'guest_arch':a.target_arch,'cross_compile':a.target_arch!=a.exec_arch,
        }
        (stage/'manifest.json').write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
        rows=[]
        for rel in sorted(expected_outer(version)-{'SHA256SUMS'}): rows.append(f'{sha_file(stage/rel)}  {rel}')
        (stage/'SHA256SUMS').write_text('\n'.join(rows)+'\n')
        out=pathlib.Path(a.output or f'buildenv-{a.provider}-{a.kernel_release}-{a.target_arch}--{aid[:16]}.klabbuildenv').resolve()
        out.parent.mkdir(parents=True,exist_ok=True)
        subprocess.run(['tar','-C',str(stage),'--zstd','-cf',str(out),'FORMAT_VERSION','manifest.json','SHA256SUMS','payload','spec'],check=True)
        verify_archive(out,deep=True)
        print(f'{aid}  {out}')
    finally: shutil.rmtree(stage,ignore_errors=True)

from klab_paths import root_home

def object_dir(home, aid): return pathlib.Path(home)/'artifacts/buildenvs/sha256'/aid

def cmd_import(a):
    m=verify_archive(a.file,deep=True); home=pathlib.Path(root_home(a.home)).resolve(); obj=object_dir(home,m['id']); obj.parent.mkdir(parents=True,exist_ok=True)
    if obj.exists():
        try:
            verify_installed(obj)
            print(obj); return
        except SystemExit:
            if not a.force: die(f'installed buildenv {m["id"]} failed integrity verification; use --force to replace')
            shutil.rmtree(obj)
    tmp=pathlib.Path(tempfile.mkdtemp(prefix='klab-buildenv-import-',dir=str(obj.parent)))
    try:
        obj.parent.mkdir(parents=True,exist_ok=True)
        stage=tmp/'stage'; root=tmp/'root'; stage.mkdir(); root.mkdir()
        safe_tar_members(a.file); extract_zst_tar(a.file,stage)
        mm=verify_extracted(stage,deep=False)
        extract_zst_tar(stage/'payload/root.tar.zst',root)
        validate_tree(root)
        if tree_digest(root)!=mm['root_tree_sha256']: die('imported root digest mismatch')
        final=tmp/mm['id']; final.mkdir()
        shutil.move(str(root),str(final/'root'))
        shutil.copy2(stage/'manifest.json',final/'manifest.json'); shutil.copy2(stage/'spec/package-manifest.txt',final/'package-manifest.txt')
        if mm.get('format_version',1)>=2: shutil.copy2(stage/'spec/installed-packages.tsv',final/'installed-packages.tsv')
        if mm.get('format_version',1)>=4:
            shutil.copy2(stage/'spec/dependency-archives.sha256',final/'dependency-archives.sha256')
            shutil.copy2(stage/'spec/dependency-provenance.json',final/'dependency-provenance.json')
            (final/'dependency-archives').mkdir()
            extract_zst_tar(stage/'payload/dependency-archives.tar.zst',final/'dependency-archives')
        (final/'TYPE').write_text('buildenv\n')
        verify_installed(final)
        os.replace(final,obj)
        print(obj)
    finally: shutil.rmtree(tmp,ignore_errors=True)

def verify_installed(obj):
    obj=pathlib.Path(obj)
    m=json.loads((obj/'manifest.json').read_text())
    if m.get('format')!=FORMAT or m.get('artifact_type')!='buildenv': die('installed object is not a buildenv')
    version=int(m.get('format_version',0) or 0)
    if version not in SUPPORTED_VERSIONS: die('unsupported installed buildenv format version')
    spec={k:m.get(k,'') for k in spec_keys(version)}
    if artifact_id(spec)!=m.get('id') or obj.name!=m.get('id'): die('installed buildenv identity mismatch')
    if sha_file(obj/'package-manifest.txt')!=m.get('package_manifest_sha256'): die('installed package manifest changed')
    if version>=2 and sha_file(obj/'installed-packages.tsv')!=m.get('installed_inventory_sha256'): die('installed package inventory changed')
    if version>=4:
        if sha_file(obj/'dependency-archives.sha256')!=m.get('dependency_archive_manifest_sha256'): die('installed dependency archive manifest changed')
        if sha_file(obj/'dependency-provenance.json')!=m.get('dependency_provenance_sha256'): die('installed dependency provenance changed')
        validate_dependency_closure(obj/'dependency-archives',obj/'dependency-archives.sha256',obj/'dependency-provenance.json',m['provider'],m['release'],obj/'installed-packages.tsv')
        if tree_digest(obj/'dependency-archives')!=m.get('dependency_archive_tree_sha256'): die('installed dependency archive closure changed')
    validate_tree(obj/'root')
    if version>=3 and m.get('compiler_contract')=='distro-native-v1': validate_host_tool_owners(obj/'root', obj/'installed-packages.tsv')
    if tree_digest(obj/'root')!=m.get('root_tree_sha256'): die('installed buildenv root changed')
    return m


def cmd_assert_installed(a):
    home=pathlib.Path(root_home(a.home)).resolve()
    obj=object_dir(home,a.id)
    m=verify_installed(obj)
    checks={
      'provider':a.provider,
      'release':a.release,
      'kernel_release':a.kernel_release,
      'target_arch':a.target_arch,
      'exec_arch':a.exec_arch,
      'toolchain_tree_sha256':a.toolchain_tree_sha256,
      'toolchain_family':a.toolchain_family,
      'toolchain_version':a.toolchain_version,
      'toolchain_target':a.toolchain_target,
      'toolchain_cc_relpath':a.toolchain_cc_relpath,
      'compiler_contract':a.compiler_contract,
      'distro_toolchain_id':a.distro_toolchain_id,
    }
    for key,expected in checks.items():
        if expected is None or expected=='':
            continue
        actual=str(m.get(key,'') or '')
        if key in ('target_arch','exec_arch'):
            aliases={'amd64':'x86_64','x86_64':'x86_64','i386':'i386','i486':'i386','i586':'i386','i686':'i386','x86':'i386','arm64':'aarch64','aarch64':'aarch64','armv7':'armv7','armv7l':'armv7','armhf':'armv7','arm':'armv7'}
            actual=aliases.get(actual,actual); expected=aliases.get(expected,expected)
        if actual != expected:
            die(f'installed buildenv binding mismatch for {key}: expected {expected}, got {actual or "<empty>"}')
    if a.json:
        print(json.dumps(m,sort_keys=True,separators=(',',':')))
    else:
        print(obj)

def cmd_verify(a):
    m=verify_archive(a.file,deep=a.deep); print(m['id'])

def cmd_inspect(a):
    m=verify_archive(a.file,deep=False); print(json.dumps(m,indent=2,sort_keys=True))


def cmd_list(a):
    home=pathlib.Path(root_home(a.home)).resolve()
    base=home/'artifacts/buildenvs/sha256'
    if not base.is_dir():
        return
    for obj in sorted(base.iterdir(), key=lambda p:p.name):
        if not obj.is_dir() or not (obj/'TYPE').is_file():
            continue
        try:
            if (obj/'TYPE').read_text().strip()!='buildenv':
                continue
            m=verify_installed(obj)
            print(f"{m['id']}\t{m['provider']}:{m['release']}:{m['kernel_release']}\t{m['target_arch']}\t{m['exec_arch']}")
        except (OSError,ValueError,KeyError,json.JSONDecodeError,SystemExit) as e:
            print(f"{obj.name}\tCORRUPT\t{e}", file=sys.stderr)

def cmd_lookup(a):
    home=pathlib.Path(root_home(a.home)).resolve(); obj=object_dir(home,a.id)
    verify_installed(obj); print(obj)

def main():
    ap=argparse.ArgumentParser(); sp=ap.add_subparsers(dest='cmd',required=True)
    p=sp.add_parser('create'); p.add_argument('--root',required=True); p.add_argument('--provider',required=True); p.add_argument('--release',required=True); p.add_argument('--kernel-release',required=True); p.add_argument('--target-arch',required=True); p.add_argument('--exec-arch',required=True); p.add_argument('--provider-image',default=''); p.add_argument('--recipe-version',default='buildenv-v1'); p.add_argument('--build-dir',required=True); p.add_argument('--source-dir',default=''); p.add_argument('--package-manifest',required=True); p.add_argument('--installed-inventory',required=True); p.add_argument('--dependency-archives'); p.add_argument('--dependency-provenance'); p.add_argument('--compiler-contract',choices=('gcc-v1','distro-native-v1'),default='gcc-v1'); p.add_argument('--distro-toolchain-id',default=''); p.add_argument('--toolchain-tree-sha256',default=''); p.add_argument('--toolchain-family',default=''); p.add_argument('--toolchain-version',default=''); p.add_argument('--toolchain-target',default=''); p.add_argument('--toolchain-cc-relpath',default=''); p.add_argument('-o','--output'); p.set_defaults(func=cmd_create)
    p=sp.add_parser('verify'); p.add_argument('file'); p.add_argument('--deep',action='store_true'); p.set_defaults(func=cmd_verify)
    p=sp.add_parser('inspect'); p.add_argument('file'); p.set_defaults(func=cmd_inspect)
    p=sp.add_parser('import'); p.add_argument('file'); p.add_argument('--home'); p.add_argument('--force',action='store_true'); p.set_defaults(func=cmd_import)
    p=sp.add_parser('lookup'); p.add_argument('id'); p.add_argument('--home'); p.set_defaults(func=cmd_lookup)
    p=sp.add_parser('list'); p.add_argument('--home'); p.set_defaults(func=cmd_list)
    p=sp.add_parser('assert-installed'); p.add_argument('id'); p.add_argument('--home'); p.add_argument('--provider'); p.add_argument('--release'); p.add_argument('--kernel-release'); p.add_argument('--target-arch'); p.add_argument('--exec-arch'); p.add_argument('--compiler-contract'); p.add_argument('--distro-toolchain-id'); p.add_argument('--toolchain-tree-sha256'); p.add_argument('--toolchain-family'); p.add_argument('--toolchain-version'); p.add_argument('--toolchain-target'); p.add_argument('--toolchain-cc-relpath'); p.add_argument('--json',action='store_true'); p.set_defaults(func=cmd_assert_installed)
    a=ap.parse_args(); a.func(a)
if __name__=='__main__': main()
