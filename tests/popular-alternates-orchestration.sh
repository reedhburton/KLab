#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/klab-popular-alternates-queue.sh"
bash -n "$f"
grep -Fq 'matrix/popular-alternate-kernels.tsv' "$f"
grep -Fq 'KLAB_CROSS_SECTIONS=arch' "$f"
grep -Fq 'klab-distro-expansion-queue.sh' "$f"
grep -Fq 'klab-cross-distro-queue-r4.sh' "$f"
for family in arch-linux-current arch-linux-lts arch-linux-zen arch-linux-hardened; do
  grep -Fq "$family" "$ROOT/klab-cross-distro-queue-r4.sh"
done
echo 'PASS: provider-validated Ubuntu/Debian alternates followed by four exact Arch families'
