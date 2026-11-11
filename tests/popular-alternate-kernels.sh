#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
m="$ROOT/matrix/popular-alternate-kernels.tsv"
[[ -f "$m" ]]
[[ "$(head -n1 "$m")" == $'provider\trelease\tarch\tpattern\tlatest' ]]
for flavour in lowlatency aws azure gcp oem realtime oracle gke; do
  grep -Eq "^ubuntu[[:space:]].*[[:space:]]-${flavour}\\\$[[:space:]]" "$m"
  grep -Eq "generic.*lowlatency.*aws.*azure.*gcp.*oracle.*oem.*realtime.*gke" "$ROOT/providers/ubuntu.sh"
done
for release in bullseye bookworm trixie; do
  for suffix in amd64 cloud-amd64 rt-amd64; do
    grep -q "^debian	$release	x86_64	-$suffix\$	2$" "$m"
  done
done
[[ "$(awk -F '\t' 'NR>1 {s+=$5} END{print s}' "$m")" == 50 ]]
! grep -q -- '-generic\$' "$m"
echo 'PASS: bounded Ubuntu alternate-flavour and Debian standard/cloud/RT matrix'
