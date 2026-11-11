#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/pkgs"; printf payload >"$T/pkgs/gcc.deb"
SHA=$(sha256sum "$T/pkgs/gcc.deb" | awk '{print $1}')
printf 'gcc\t6.3.0\tamd64\n' >"$T/packages.tsv"
cat >"$T/compiler.json" <<'JSON'
{"cc_path":"/usr/bin/gcc","cc_version":"6.3.0","cc_target":"x86_64-linux-gnu","as_path":"/usr/bin/as","as_version":"2.28","ld_path":"/usr/bin/ld","ld_version":"2.28"}
JSON
python3 - "$T/provenance.json" "$SHA" <<'PY'
import hashlib,json,sys
repo='deb http://old-releases.ubuntu.com/ubuntu zesty main\n'; keys='ubuntu-key\n'; meta=[['zesty_InRelease','0'*64]]
h=lambda s:hashlib.sha256(s.encode()).hexdigest()
x={'schema':'klab-repository-provenance-v1','provider':'ubuntu','release':'17.04','repository_config':repo,'repository_config_sha256':h(repo),'key_inventory':keys,'key_inventory_sha256':h(keys),'repository_metadata':meta,'repository_metadata_sha256':h(json.dumps(meta,separators=(',',':'))),'apt_package_metadata':[{'name':'gcc','version':'6.3.0','arch':'amd64','file':'gcc.deb','sha256':sys.argv[2]}]}
open(sys.argv[1],'w').write(json.dumps(x,sort_keys=True))
PY
"$ROOT/klab-distro-toolchain.sh" create --packages "$T/pkgs" --inventory "$T/packages.tsv" --compiler-json "$T/compiler.json" --provenance "$T/provenance.json" --provider ubuntu --release 17.04 --arch x86_64 -o "$T/good.klabdistrotoolchain" >/dev/null
"$ROOT/klab-distro-toolchain.sh" verify "$T/good.klabdistrotoolchain" >/dev/null
python3 - "$T/provenance.json" <<'PY'
import json,sys
p=sys.argv[1]; x=json.load(open(p)); x['apt_package_metadata'][0]['sha256']='f'*64; open(p,'w').write(json.dumps(x))
PY
if "$ROOT/klab-distro-toolchain.sh" create --packages "$T/pkgs" --inventory "$T/packages.tsv" --compiler-json "$T/compiler.json" --provenance "$T/provenance.json" --provider ubuntu --release 17.04 --arch x86_64 -o "$T/bad.klabdistrotoolchain" >/dev/null 2>&1; then
 echo 'FAIL: accepted DEB whose bytes disagree with authenticated APT package metadata' >&2; exit 1
fi

grep -Fq 'elif have_candidate \"linux-image-unsigned-$krel\"' "$ROOT/lib/backends/apt.sh" || { echo 'FAIL: signed/unsigned APT kernel image selection is not exclusive' >&2; exit 1; }

# Legacy metadata is accepted only when its advertised digest matches the bytes;
# KLab's independent SHA256 remains mandatory.
python3 - "$T/provenance.json" "$SHA" <<'PYLEGACY'
import hashlib,json,sys
p=sys.argv[1]; payload=b'payload'; repo='legacy\n'; keys='key\n'; meta=[['Release','0'*64]]
h=lambda s:hashlib.sha256(s.encode()).hexdigest()
x={'schema':'klab-repository-provenance-v1','provider':'ubuntu','release':'12.04','repository_config':repo,'repository_config_sha256':h(repo),'key_inventory':keys,'key_inventory_sha256':h(keys),'repository_metadata':meta,'repository_metadata_sha256':h(json.dumps(meta,separators=(',',':'))),'apt_package_metadata':[{'name':'gcc','version':'6.3.0','arch':'amd64','file':'gcc.deb','metadata_digest_algorithm':'SHA1','metadata_digest':hashlib.sha1(payload).hexdigest(),'sha256':sys.argv[2]}]}
open(p,'w').write(json.dumps(x,sort_keys=True))
PYLEGACY
"$ROOT/klab-distro-toolchain.sh" create --packages "$T/pkgs" --inventory "$T/packages.tsv" --compiler-json "$T/compiler.json" --provenance "$T/provenance.json" --provider ubuntu --release 12.04 --arch x86_64 -o "$T/legacy.klabdistrotoolchain" >/dev/null
python3 - "$T/provenance.json" <<'PYLEGACY'
import json,sys
p=sys.argv[1]; x=json.load(open(p)); x['apt_package_metadata'][0]['metadata_digest']='0'*40; open(p,'w').write(json.dumps(x))
PYLEGACY
if "$ROOT/klab-distro-toolchain.sh" create --packages "$T/pkgs" --inventory "$T/packages.tsv" --compiler-json "$T/compiler.json" --provenance "$T/provenance.json" --provider ubuntu --release 12.04 --arch x86_64 -o "$T/bad-legacy.klabdistrotoolchain" >/dev/null 2>&1; then
 echo 'FAIL: accepted DEB whose bytes disagree with authenticated legacy APT digest' >&2; exit 1
fi
grep -Fq 'for candidate in SHA256 SHA1 MD5sum' "$ROOT/lib/backends/apt.sh"
grep -Fq 'v=\$(apt-cache policy \"\$p\"' "$ROOT/lib/backends/apt.sh"
grep -Fq 'missing=\$(comm -23 /out/packages.tsv /out/archives.tsv)' "$ROOT/lib/backends/apt.sh"
grep -Fq 'cp /out/archives.tsv /out/packages.tsv' "$ROOT/lib/backends/apt.sh"
echo PASS
