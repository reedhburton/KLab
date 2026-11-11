#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir "$T/pkgs"; printf rpm >"$T/pkgs/a.rpm"; printf 'a\t1:1-1\tx86_64\n' >"$T/inv.tsv"
printf '%s\n' '{"cc_path":"/usr/bin/gcc","cc_version":"6.3.0","cc_target":"x86_64-redhat-linux","as_path":"/usr/bin/as","as_version":"2.27","ld_path":"/usr/bin/ld","ld_version":"2.27"}' >"$T/compiler.json"
python3 - "$T" <<'PY'
import hashlib,json,sys,os
T=sys.argv[1]; h=lambda s:hashlib.sha256(s.encode()).hexdigest(); f=T+'/pkgs/a.rpm'; d=hashlib.sha256(open(f,'rb').read()).hexdigest(); meta=[]
x={'schema':'klab-repository-provenance-v1','provider':'centos','release':'7','repository_config':'repo','key_inventory':'key','repository_metadata':meta,'repository_config_sha256':h('repo'),'key_inventory_sha256':h('key'),'repository_metadata_sha256':h(json.dumps(meta,separators=(',',':'))),'package_signatures':[{'file':'a.rpm','sha256':d,'verified':True,'evidence':'a.rpm: rsa sha1 (md5) pgp md5 OK'}]}
open(T+'/prov.json','w').write(json.dumps(x))
PY
"$ROOT/klab-distro-toolchain.sh" create --packages "$T/pkgs" --inventory "$T/inv.tsv" --compiler-json "$T/compiler.json" --provenance "$T/prov.json" --provider centos --release 7 --arch x86_64 -o "$T/good.klabdistrotoolchain" >/dev/null
python3 - "$T/prov.json" <<'PY'
import json,sys
p=sys.argv[1]; x=json.load(open(p)); x['package_signatures'][0]['verified']=False; open(p,'w').write(json.dumps(x))
PY
if "$ROOT/klab-distro-toolchain.sh" create --packages "$T/pkgs" --inventory "$T/inv.tsv" --compiler-json "$T/compiler.json" --provenance "$T/prov.json" --provider centos --release 7 --arch x86_64 -o "$T/bad.klabdistrotoolchain" >/dev/null 2>&1; then echo 'FAIL: unverified RPM signature accepted' >&2; exit 1; fi
echo 'rpm signature provenance: PASS'
