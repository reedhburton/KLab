#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
for f in "$ROOT/klab-daytime-sweep-v1.sh" "$ROOT/klab-cross-distro-queue-v2.sh"; do
  [[ -x "$f" ]] || { echo "missing executable sweep script: $f" >&2; exit 1; }
  bash -n "$f"
done
grep -Fq 'KLAB_FEDORA_KOJI_FALLBACK=$mode' "$ROOT/klab-daytime-sweep-v1.sh"
grep -Fq 'KLAB_DAY_FORCE_FEDORA_FALLBACK:-29,44' "$ROOT/klab-daytime-sweep-v1.sh"
grep -Fq 'daytime-sweep-${RUN_ID}-results.tar.gz' "$ROOT/klab-daytime-sweep-v1.sh"
for d in mint debian centos arch manjaro oracle amazon opensuse kali proxmox rocky alma alpine; do
  grep -Fq "section_enabled $d" "$ROOT/klab-cross-distro-queue-v2.sh" || { echo "missing cross-distro section: $d" >&2; exit 1; }
done
grep -Fq 'for pkg in linux61 linux66 linux612 linux618 linux72' "$ROOT/klab-cross-distro-queue-v2.sh"
grep -Fq 'proxmox-kernel-7.0 proxmox-headers-7.0' "$ROOT/klab-cross-distro-queue-v2.sh"
echo 'daytime-sweep-wiring: PASS'
