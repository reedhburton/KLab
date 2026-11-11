#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
conf="$ROOT/klab-buildroot-conformance.sh"; runner="$ROOT/kernel-lab.sh"
grep -Fq 'test -d /sys/class || test -d /sys/devices' "$conf"
grep -Fq '2.[1-4].*)' "$conf"
grep -Fq '2.0.*) test -d /proc' "$conf"
grep -Fq "route add -net '" "$runner"
! grep -Fq 'ping -c 1 -W 2 10.0.2.2' "$conf"
grep -Fq 'HOST_CFLAGS="-O2 -std=gnu17" HOST_CXXFLAGS="-O2 -std=gnu++17"' "$runner"
echo 'buildroot-legacy-host-compat: PASS'
