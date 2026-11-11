#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/kernel-lab.sh"
count="$(grep -Fo 'chown -R 0:0 /root; chmod 700 /root /root/.ssh' "$F" | wc -l)"
[[ "$count" -ge 2 ]]
bash -n "$F"
echo 'PASS: disposable Dropbear roots become guest-root-owned before authentication'
