#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$ROOT/klab-all-five-linux-queue.sh"
grep -Fq -- '--userspace buildroot:minimal' "$ROOT/klab-all-five-linux-queue.sh"
grep -Fq -- '--ssh-auth key' "$ROOT/klab-all-five-linux-queue.sh"
grep -Fq 'ssh-keygen -q -t rsa -b 3072' "$ROOT/klab-all-five-linux-queue.sh"
grep -Fq 'HostkeyAlgorithms=+ssh-rsa' "$ROOT/klab-all-five-linux-queue.sh"
grep -Fq 'KLAB_EXACT_SSH_PASS' "$ROOT/klab-all-five-linux-queue.sh"
echo 'PASS: Linux all-five queue gates minimal module/process and native SSH'
