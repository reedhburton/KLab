#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
P="$ROOT/lib/multiguest_plan.py"
S="$ROOT/examples/multiguest/two-guest-network.json"
C="$ROOT/examples/multiguest/three-guest-kernel-span.json"
R="$ROOT/examples/multiguest/two-lan-router-r16.json"
F="$ROOT/examples/multiguest/link-flap-recovery-r16.json"
"$P" validate "$S" >/dev/null
"$P" validate "$C" >/dev/null
"$P" validate "$R" >/dev/null
"$P" validate "$F" >/dev/null
[[ "$("$P" guests "$S" | wc -l)" -eq 2 ]]
[[ "$("$P" guests "$C" | wc -l)" -eq 3 ]]
"$P" guests "$S" | grep -q $'server\tupstream:v6.6\tx86_64\tnormal\tbuildroot:minimal\t10.77.0.11/24'
[[ "$("$P" gates "$C" | cut -f1 | sort -u)" == start ]]
[[ "$("$P" networks "$R" | wc -l)" -eq 2 ]]
[[ "$("$P" interfaces "$R" | awk '$1=="router"{n++} END{print n+0}')" -eq 2 ]]
"$P" routes "$R" | grep -q $'server\t10.77.20.0/24\t10.77.10.1'
"$P" actions "$F" | grep -q $'client-link-flap\tlink-flap\t'
T="$(mktemp)"; trap 'rm -f "$T"' EXIT
python3 - "$S" "$T" <<'PY'
import json,sys
with open(sys.argv[1]) as f:o=json.load(f)
o['guests'][1]['ip']=o['guests'][0].get('ip','10.77.0.11/24')
with open(sys.argv[2],'w') as f:json.dump(o,f)
PY
if "$P" validate "$T" >/dev/null 2>&1; then echo 'duplicate IP accepted' >&2; exit 1; fi
echo PASS
