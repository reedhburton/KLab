#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/klab-legacy-network-v1.sh"
[[ -x "$SCRIPT" ]]
grep -Fq 'ping -c 3' "$SCRIPT"
grep -Fq 'NETWORK_PASS target=' "$SCRIPT"
grep -Fq 'ensure_linux22_guest_busybox()' "$ROOT/kernel-lab.sh"
grep -Fq 'ensure_linux24_guest_busybox()' "$ROOT/kernel-lab.sh"
grep -Fq 'validate_guest_busybox "$arch" "$tmp"' "$ROOT/kernel-lab.sh"
python3 - "$ROOT/legacy/targets-v1.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); t=next(x for x in m['targets'] if x['id']=='linux-2.6.32-x86_64')
assert t['achieved_level']=='NETWORK_PASS'
PY
echo 'PASS: formal legacy network gate and i386 userspace pin'
