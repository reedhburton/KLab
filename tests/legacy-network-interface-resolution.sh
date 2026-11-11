#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/kernel-lab.sh"
grep -Fq "[ ! -r /sys/class/net/'\$iface'/address ]" "$f"
grep -Fq 'legacy_config=1' "$f"
grep -Fq "route add -net '\$network' netmask '\$mask' dev '\$iface'" "$f"
bash -n "$f"
echo 'PASS: pre-sysfs kernels retain the explicit guest interface name'
