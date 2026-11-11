#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
bash -n "$ROOT/tools/ubuntu-kernel-catalog.sh" "$ROOT/klab-ubuntu-generic-queue.sh"
grep -Fq '^linux-image-[0-9]+[.][0-9]+[.][0-9]+-[0-9]+-generic$' "$ROOT/tools/ubuntu-kernel-catalog.sh"
grep -Fq 'KLAB_QUEUE_FREE_GIB:-20' "$ROOT/klab-ubuntu-generic-queue.sh"
grep -Fq 'kernel-lab.sh" fetch' "$ROOT/klab-ubuntu-generic-queue.sh"
grep -Fq 'fetch "$target" >"$log"' "$ROOT/klab-ubuntu-generic-queue.sh" || { echo 'queue does not use one-argument fetch' >&2; exit 1; }
! grep -Fq 'fetch "$target" --arch' "$ROOT/klab-ubuntu-generic-queue.sh" || { echo 'queue passes unsupported fetch options' >&2; exit 1; }
grep -Fqx $'ubuntu\t26.04\tx86_64\t-generic$\tall' "$ROOT/matrix/popular-distro-expansion.tsv" || {
  echo 'Ubuntu 26.04 generic catalog is not configured for complete retention' >&2; exit 1;
}
echo 'ubuntu kernel catalog and bounded queue: PASS'
