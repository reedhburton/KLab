#!/usr/bin/env python3
"""Create a KLab V4 dependency archive closure without network access."""
import argparse, hashlib, json, pathlib, shutil, subprocess, tarfile

EXTENSIONS={'.deb','.rpm','.apk'}

def die(message): raise SystemExit(f'seal-dependency-closure: ERROR: {message}')
def sha(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''): h.update(block)
    return h.hexdigest()

def command(args):
    try: return subprocess.check_output(args,text=True,stderr=subprocess.DEVNULL).strip()
    except (OSError,subprocess.CalledProcessError) as e: die(f'cannot read package metadata with {args[0]}: {e}')

def deb_identity(path):
    fields=[command(['dpkg-deb','-f',str(path),field]) for field in ('Package','Version','Architecture')]
    if len(fields)!=3 or not all(fields): die(f'incomplete DEB identity: {path.name}')
    return tuple(fields)

def rpm_identity(path):
    fields=command(['rpm','-qp','--qf','%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\t%{ARCH}',str(path)]).split('\t')
    if len(fields)!=3 or not all(fields): die(f'incomplete RPM identity: {path.name}')
    return tuple(fields)

def apk_identity(path):
    try:
        with tarfile.open(path,'r:*') as tf:
            member=next((m for m in tf if pathlib.PurePosixPath(m.name).name=='.PKGINFO'),None)
            if member is None: die(f'APK has no .PKGINFO: {path.name}')
            data=tf.extractfile(member).read().decode('utf-8','strict')
    except (tarfile.TarError,OSError,UnicodeError) as e: die(f'cannot read APK metadata {path.name}: {e}')
    values={}
    for line in data.splitlines():
        if ' = ' in line:
            key,value=line.split(' = ',1); values.setdefault(key,value)
    fields=(values.get('pkgname'),values.get('pkgver'),values.get('arch'))
    if not all(fields): die(f'incomplete APK identity: {path.name}')
    return fields

def package_identity(path):
    return {'.deb':deb_identity,'.rpm':rpm_identity,'.apk':apk_identity}[path.suffix](path)

def inventory(path):
    rows=set()
    for lineno,line in enumerate(path.read_text().splitlines(),1):
        if not line.strip(): continue
        cols=line.split('\t')
        if len(cols)!=3 or not all(cols): die(f'malformed installed inventory line {lineno}')
        row=tuple(cols)
        if row in rows: die(f'duplicate installed inventory row: {row}')
        rows.add(row)
    if not rows: die('installed inventory is empty')
    return rows

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--packages',required=True,type=pathlib.Path)
    ap.add_argument('--installed-inventory',required=True,type=pathlib.Path)
    ap.add_argument('--archive-identities',type=pathlib.Path)
    ap.add_argument('--provider',required=True); ap.add_argument('--release',required=True)
    ap.add_argument('--repository',action='append',nargs=2,metavar=('URL','METADATA_FILE'),required=True)
    ap.add_argument('--output',required=True,type=pathlib.Path)
    ap.add_argument('--provenance-output',type=pathlib.Path)
    a=ap.parse_args()
    if not a.packages.is_dir(): die('package directory does not exist')
    if not a.installed_inventory.is_file(): die('installed inventory does not exist')
    if a.output.exists() and any(a.output.iterdir()): die('output directory is not empty')
    a.output.mkdir(parents=True,exist_ok=True)
    package_files=sorted((p for p in a.packages.iterdir() if p.is_file() and p.suffix in EXTENSIONS),key=lambda p:p.name)
    if not package_files: die('no DEB, RPM, or APK archives found')
    supplied={}
    if a.archive_identities:
        if not a.archive_identities.is_file(): die('archive identity manifest does not exist')
        for lineno,line in enumerate(a.archive_identities.read_text().splitlines(),1):
            if not line.strip(): continue
            cols=line.split('\t')
            if len(cols)!=5 or not all(cols): die(f'malformed archive identity line {lineno}')
            name,digest,pkg,version,arch=cols
            if '/' in name or name in ('.','..'): die(f'unsafe archive identity filename: {name}')
            if len(digest)!=64 or any(c not in '0123456789abcdefABCDEF' for c in digest): die(f'malformed archive identity digest: {name}')
            digest=digest.lower(); identity=(pkg,version,arch)
            if name in supplied and supplied[name][0]!=digest: die(f'conflicting archive identity digest: {name}')
            supplied.setdefault(name,(digest,set()))[1].add(identity)
        if set(supplied)!={x.name for x in package_files}: die('archive identity manifest file set mismatch')
    package_rows=[]; identities=set(); names=set()
    for source in package_files:
        if source.name in names: die(f'duplicate archive basename: {source.name}')
        names.add(source.name)
        if supplied:
            expected_sha,source_identities=supplied[source.name]
            if sha(source)!=expected_sha: die(f'archive identity checksum mismatch: {source.name}')
        else: source_identities={package_identity(source)}
        target=a.output/source.name; shutil.copyfile(source,target); target_sha=sha(target)
        for identity in sorted(source_identities):
            if identity in identities: die(f'duplicate package identity: {identity}')
            identities.add(identity)
            package_rows.append({'file':source.name,'sha256':target_sha,'name':identity[0],'version':identity[1],'arch':identity[2]})
    installed=inventory(a.installed_inventory)
    if identities!=installed:
        die(f'archive identities do not equal installed inventory: missing={sorted(installed-identities)} extra={sorted(identities-installed)}')
    metadata_dir=a.output/'repository-metadata'; metadata_dir.mkdir()
    repositories=[]
    for index,(url,raw_path) in enumerate(a.repository,1):
        source=pathlib.Path(raw_path)
        if not source.is_file(): die(f'repository metadata does not exist: {source}')
        target=metadata_dir/f'{index:03d}-{source.name}'
        shutil.copyfile(source,target)
        repositories.append({'url':url,'metadata_file':target.relative_to(a.output).as_posix(),'metadata_sha256':sha(target)})
    with open(a.output/'PACKAGES.sha256','w') as f:
        archive_sums={row['file']:row['sha256'] for row in package_rows}
        for name in sorted(archive_sums): f.write(f"{archive_sums[name]}  {name}\n")
    provenance={'schema':'klab-buildenv-dependency-provenance-v1','provider':a.provider,'release':a.release,'repositories':repositories,'packages':package_rows}
    provenance_path=a.provenance_output or a.output.parent/(a.output.name+'-provenance.json')
    try: provenance_path.resolve().relative_to(a.output.resolve())
    except ValueError: pass
    else: die('provenance output must be outside the dependency archive directory')
    if provenance_path.exists(): die(f'provenance output already exists: {provenance_path}')
    provenance_path.parent.mkdir(parents=True,exist_ok=True)
    provenance_path.write_text(json.dumps(provenance,indent=2,sort_keys=True)+'\n')
    print(provenance_path)
if __name__=='__main__': main()
