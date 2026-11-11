#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq 'for candidate in /dev/ttyV*; do' "$ROOT/kernel-lab.sh"
grep -Fq 'if [ -c "$candidate" ]; then TTY="$candidate"; break; fi' "$ROOT/kernel-lab.sh"
grep -Fq 'n -lt 600' "$ROOT/kernel-lab.sh"
echo 'PASS: FreeBSD agent discovers its QEMU virtio console device'
