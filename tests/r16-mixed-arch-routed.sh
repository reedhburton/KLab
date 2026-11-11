#!/usr/bin/env bash
set -euo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SC="$SELF/examples/multiguest/routed-mixed-arch-r16.json"
PLAN="$SELF/lib/multiguest_plan.py"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
"$PLAN" validate "$SC"
"$PLAN" guests "$SC" > "$tmp/guests.tsv"
grep -Eq '^client-x86[[:space:]].*[[:space:]]x86_64[[:space:]]' "$tmp/guests.tsv"
grep -Eq '^router-arm64[[:space:]].*[[:space:]]aarch64[[:space:]]' "$tmp/guests.tsv"
grep -Eq '^server-i386[[:space:]].*[[:space:]]i386[[:space:]]' "$tmp/guests.tsv"
python3 - "$SC" <<'PY'
import json,sys,ipaddress
s=json.load(open(sys.argv[1]))
g={x["id"]:x for x in s["guests"]}
assert set(g)=={"client-x86","router-arm64","server-i386"}
assert g["client-x86"]["arch"]=="x86_64"
assert g["router-arm64"]["arch"]=="aarch64" and g["router-arm64"]["forward_ipv4"] is True
assert g["server-i386"]["arch"]=="i386"
assert len(g["router-arm64"]["interfaces"])==2
assert {x["network"] for x in g["router-arm64"]["interfaces"]}=={"lan-client","lan-server"}
assert g["client-x86"]["routes"]==[{"to":"10.77.90.0/24","via":"10.77.80.1"}]
assert g["server-i386"]["routes"]==[{"to":"10.77.80.0/24","via":"10.77.90.1"}]
p=g["client-x86"]["processes"][0]
assert p["depends_on"]==[{"guest":"server-i386","process":"server","state":"ready"}]
PY
# Ensure all architecture execution profiles remain resolvable without launching QEMU.
grep -q '^QEMU_BINARY=qemu-system-x86_64$' "$SELF/architectures/x86_64.conf"
grep -q '^QEMU_NET_DEVICE=e1000$' "$SELF/architectures/x86_64.conf"
grep -q '^QEMU_BINARY=qemu-system-aarch64$' "$SELF/architectures/aarch64.conf"
grep -q '^QEMU_NET_DEVICE=virtio-net-device$' "$SELF/architectures/aarch64.conf"
grep -q '^QEMU_BINARY=qemu-system-i386$' "$SELF/architectures/i386.conf"
grep -q '^QEMU_NET_DEVICE=e1000$' "$SELF/architectures/i386.conf"
echo "PASS r16 mixed-architecture routed model"
