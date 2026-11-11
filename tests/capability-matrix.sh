#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
out=$(mktemp -d); trap 'rm -rf "$out"' EXIT
mkdir -p "$out/root/targets/kernels/linuxish/1/x86_64/1.2.3" \
  "$out/root/targets/kernels/freebsd/15/aarch64/aarch64" \
  "$out/root/artifacts/userspaces/native/linuxish/1/x86_64" \
  "$out/root/artifacts/userspaces/buildroot/2025/minimal/x86_64"
cat > "$out/root/targets/kernels/linuxish/1/x86_64/1.2.3/bundle.env" <<E
BUNDLE_PROVIDER=linuxish
BUNDLE_DISTRO_RELEASE=1
BUNDLE_KERNEL_RELEASE=1.2.3
BUNDLE_ARCH=x86_64
BUNDLE_BUILD_DIR=/build
BUNDLE_MODULES_DIR=/modules
E
cat > "$out/root/targets/kernels/freebsd/15/aarch64/aarch64/bundle.env" <<E
BUNDLE_PROVIDER=freebsd
BUNDLE_BACKEND=freebsd
BUNDLE_TARGET_ID=freebsd:15:aarch64
BUNDLE_DISTRO_RELEASE=15
BUNDLE_KERNEL_RELEASE=aarch64
BUNDLE_ARCH=aarch64
E
: > "$out/root/artifacts/userspaces/native/linuxish/1/x86_64/metadata.env"
: > "$out/root/artifacts/userspaces/buildroot/2025/minimal/x86_64/metadata.env"
printf 'provider\trelease\tkernel\tarch\tresult\tmodule_process_minimal\tnative_ssh\treport\nlinuxish\t1\t1.2.3\tx86_64\tPASS\tPASS\tPASS\t/report\n' > "$out/linux.tsv"
printf 'provider\trelease\tarch\tnetwork\tnative_ssh\tmodule_full_userland\tminimal_userland_gate\tresult\nfreebsd\t15\taarch64\tPASS\tPASS\tPASS\tALTERNATE_GATE_PASS\tPASS\n' > "$out/bsd.tsv"
"$ROOT/klab-capability-matrix.py" --root "$out/root" --linux-status "$out/linux.tsv" --bsd-status "$out/bsd.tsv" --out-tsv "$out/matrix.tsv" --out-md "$out/matrix.md" >/dev/null
[[ $(awk 'END{print NR-1}' "$out/matrix.tsv") == 2 ]]
[[ $(awk -F '\t' 'NR>1&&$6=="linux"&&$9=="PROVEN_MINIMAL_WORKLOAD"{n++}END{print n+0}' "$out/matrix.tsv") == 1 ]]
[[ $(awk -F '\t' 'NR>1&&$6=="freebsd"&&$7=="PROVEN_BUILD_LOAD_UNLOAD"{n++}END{print n+0}' "$out/matrix.tsv") == 1 ]]
grep -Fq 'Targets with all five requested capabilities proven end to end: 2/2' "$out/matrix.md"
grep -Fq 'MINIMAL_ALTERNATE_GATE_PROVEN' "$out/matrix.tsv"
echo 'PASS: capability matrix reports exact targets without promoting availability to proof'
