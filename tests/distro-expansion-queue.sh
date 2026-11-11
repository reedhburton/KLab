#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/klab-distro-expansion-queue.sh"; m="$ROOT/matrix/popular-distro-expansion.tsv"
bash -n "$f"
for token in 'KLAB_EXPANSION_LIMIT' 'KLAB_EXPANSION_FREE_GIB' 'KLAB_EXPANSION_WORKERS' 'KLAB_EXPANSION_PARALLEL_VALIDATE' 'timings.tsv' 'klab-native-rootfs.sh" capture' '--userspace buildroot:minimal --with-sdk --distro-toolchain' '--level full' 'grep -E -- "$pattern"' 'all) cat "$candidates"' 'sort -Vu'; do grep -Fq -- "$token" "$f"; done
for family in alpine debian fedora centos ubuntu; do grep -q "^$family"$'\t' "$m"; done
grep -q $'^ubuntu\t24.04\taarch64\t' "$m"
echo 'PASS: resumable popular-distribution discovery, preparation, and full validation queue'
for release in 20.04 22.04 24.04; do grep -q "^ubuntu	$release	x86_64	-generic\$	all$" "$m"; grep -q "^ubuntu	$release	aarch64	-generic\$	all$" "$m"; done
for boundary in \
  'kernel-lab.sh" list "$provider:$release" </dev/null' \
  'klab-native-rootfs.sh" capture "$provider" "$release" "$arch" </dev/null' \
  '--distro-toolchain -o "$bundle" </dev/null' \
  '--report-dir "$report" </dev/null'; do
  grep -Fq -- "$boundary" "$f" || { echo "FAIL: queue child can consume remaining target rows: $boundary" >&2; exit 1; }
done
echo 'PASS: expansion children cannot consume queue input'
