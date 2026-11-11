#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq -- '--preload needs LOCAL REMOTE' "$ROOT/kernel-lab.sh"
grep -Fq 'KLAB_SESSION_PRELOAD_LOCAL=' "$ROOT/kernel-lab.sh"
grep -Fq 'cp "$preload_src" "$root$preload_dst"' "$ROOT/kernel-lab.sh"
grep -Fq -- '--preload "$binary" /tmp/network-pair' "$ROOT/klab-image-tcp-gate.sh"
! grep -Fq '"$KLAB_BIN" push' "$ROOT/klab-image-tcp-gate.sh"
echo 'session boot-time preload and upload-free TCP gate: PASS'
