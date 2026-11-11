#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/pkgs"; printf x >"$T/pkgs/gcc.deb"
printf 'gcc\t6.3.0\tamd64\n' >"$T/packages.tsv"
cat >"$T/compiler.json" <<'JSON'
{"cc_path":"/usr/bin/gcc","cc_version":"6.3.0","cc_target":"x86_64-linux-gnu","as_path":"/usr/bin/as","as_version":"2.28","ld_path":"/usr/bin/ld","ld_version":"2.28"}
JSON
python3 - "$T/provenance.json" <<'PY'
import hashlib,json,sys
repo='deb http://old-releases.ubuntu.com/ubuntu zesty main\n'; keys='ubuntu-key\n'; meta=[['/var/lib/apt/lists/example_InRelease','0'*64]]
h=lambda s:hashlib.sha256(s.encode()).hexdigest()
x={'schema':'klab-repository-provenance-v1','provider':'ubuntu','release':'17.04','repository_config':repo,'repository_config_sha256':h(repo),'key_inventory':keys,'key_inventory_sha256':h(keys),'repository_metadata':meta,'repository_metadata_sha256':h(json.dumps(meta,separators=(',',':')))}
open(sys.argv[1],'w').write(json.dumps(x,sort_keys=True))
PY
"$ROOT/klab-distro-toolchain.sh" create --packages "$T/pkgs" --inventory "$T/packages.tsv" --compiler-json "$T/compiler.json" --provenance "$T/provenance.json" --provider ubuntu --release 17.04 --arch x86_64 -o "$T/good.klabdistrotoolchain" >/dev/null
"$ROOT/klab-distro-toolchain.sh" verify "$T/good.klabdistrotoolchain" >/dev/null
python3 - "$T/provenance.json" <<'PY'
import json,sys
p=sys.argv[1]; x=json.load(open(p)); x['repository_config'] += '# tampered evidence\n'; open(p,'w').write(json.dumps(x))
PY
if "$ROOT/klab-distro-toolchain.sh" create --packages "$T/pkgs" --inventory "$T/packages.tsv" --compiler-json "$T/compiler.json" --provenance "$T/provenance.json" --provider ubuntu --release 17.04 --arch x86_64 -o "$T/bad.klabdistrotoolchain" >/dev/null 2>&1; then
 echo 'FAIL: accepted provenance whose embedded config disagrees with its digest' >&2; exit 1
fi
python3 - "$T/provenance.json" <<'PY'
import hashlib,json,sys
p=sys.argv[1]; x=json.load(open(p)); x['repository_config_sha256']=hashlib.sha256(x['repository_config'].encode()).hexdigest(); x['provider']='debian'; open(p,'w').write(json.dumps(x))
PY
if "$ROOT/klab-distro-toolchain.sh" create --packages "$T/pkgs" --inventory "$T/packages.tsv" --compiler-json "$T/compiler.json" --provenance "$T/provenance.json" --provider ubuntu --release 17.04 --arch x86_64 -o "$T/bad2.klabdistrotoolchain" >/dev/null 2>&1; then
 echo 'FAIL: accepted provenance for wrong provider' >&2; exit 1
fi
echo PASS
