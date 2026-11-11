#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export KLAB_ROOT="$T/lab"
sed 's/upstream:v6.6/ubuntu:24.04:6.8.0-142-generic/g' \
  "$ROOT/examples/multiguest/two-guest-network.json" > "$T/distro.json"
"$ROOT/kernel-lab.sh" multiguest-run "$T/distro.json" --report-dir "$T/report" --dry-run > "$T/stdout"
grep -q $'^server\tubuntu:24.04:6.8.0-142-generic\tx86_64' "$T/stdout"
grep -q $'^client\tubuntu:24.04:6.8.0-142-generic\tx86_64' "$T/stdout"
python3 - "$T/report/report.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
assert r['result']=='PASS'
assert {g['target'] for g in r['guests']} == {'ubuntu:24.04:6.8.0-142-generic'}
PY
echo 'multi-guest distribution target planning: PASS'
