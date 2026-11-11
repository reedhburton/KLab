#!/usr/bin/env bash
set -euo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
D="$SELF/examples/multiguest/mixed-matrix-r16"
PLAN="$SELF/lib/multiguest_plan.py"
python3 - "$D/matrix.json" <<'PY' > /tmp/klab-r16-matrix.$$
import json,sys
m=json.load(open(sys.argv[1]))
assert len(m['stable']) >= 4
assert len(m['experimental']) >= 3
for x in m['stable']: print('stable\t'+x)
for x in m['experimental']: print('experimental\t'+x)
PY
trap 'rm -f /tmp/klab-r16-matrix.$$' EXIT
while IFS=$'\t' read -r tier rel; do
  "$PLAN" validate "$D/$rel" >/dev/null
  python3 - "$D/$rel" "$tier" <<'PY'
import json,sys
s=json.load(open(sys.argv[1])); tier=sys.argv[2]
assert s['matrix']['tier']==tier
assert len(s['networks'])==2
G={g['id']:g for g in s['guests']}
assert set(G)=={'client','router','server'}
assert G['router']['forward_ipv4'] is True and len(G['router']['interfaces'])==2
assert G['client']['arch'] != G['server']['arch']
assert G['client']['processes'][0]['depends_on'][0] == {'guest':'server','process':'server','state':'ready'}
PY
done < /tmp/klab-r16-matrix.$$
grep -q '^ARCH_STATUS=stable$' "$SELF/architectures/armv7.conf"
grep -q '^ARCH_STATUS=experimental$' "$SELF/architectures/mips.conf"
grep -q '^ARCH_STATUS=experimental$' "$SELF/architectures/mipsel.conf"
grep -q 'KLAB_R16_EXPERIMENTAL_MATRIX:-0' "$SELF/klab-fault-overnight-r16.sh"
echo 'PASS r16 mixed architecture matrix'
