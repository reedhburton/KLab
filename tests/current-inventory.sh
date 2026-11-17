#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat >"$T/base.tsv" <<'TSV'
target	arch	family	state	offline_artifact	sources	evidence
ubuntu:24.04:old-generic	x86_64	linux	validated	yes	exact-guest-matrix	validated
TSV
printf 'upstream:v6.6\tarmv7\tupstream-linux\tpackaged\tno\t\t\n' >>"$T/base.tsv"
cat >"$T/local.tsv" <<'TSV'
target	arch	file
ubuntu:24.04:old-generic	x86_64	/cache/old/bundle.env
ubuntu:24.04:new-generic	x86_64	/cache/new/bundle.env
TSV
cat >"$T/bundles.tsv" <<'TSV'
file	target	arch	kernel_release	error
/repo/new.klab	ubuntu:24.04:new-generic	x86_64	new-generic
TSV
"$ROOT/tools/klab-current-inventory.py" --base "$T/base.tsv" --local "$T/local.tsv" --bundles "$T/bundles.tsv" --output "$T/out.tsv" >/dev/null
python3 - "$T/out.tsv" <<'PY'
import csv,sys
r={(x['target'],x['arch']):x for x in csv.DictReader(open(sys.argv[1]),delimiter='\t')}
assert len(r)==3
assert r['upstream:v6.6','armv7']['evidence']==''
old=r['ubuntu:24.04:old-generic','x86_64']
new=r['ubuntu:24.04:new-generic','x86_64']
assert old['state']=='validated' and old['local_target']=='yes' and old['offline_artifact']=='no'
assert new['state']=='packaged' and new['local_target']=='yes' and new['offline_artifact']=='yes'
assert new['family']=='linux' and 'physical-bundle-scan' in new['sources']
PY
echo 'current-inventory: PASS'
