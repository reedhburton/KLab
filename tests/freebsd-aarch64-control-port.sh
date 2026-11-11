#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq '[[ "$arch" == aarch64 ]] && tty=/dev/ttyV0.0' "$ROOT/kernel-lab.sh"
grep -Fq 'name=org.klab.agent' "$ROOT/kernel-lab.sh"
if grep -Fq 'tty=/dev/ttyV0.1' "$ROOT/kernel-lab.sh"; then
  echo 'FAIL: aarch64 agent points at nonexistent second virtio console port' >&2
  exit 1
fi
echo 'PASS: FreeBSD aarch64 agent and QEMU use the first virtio console port'
