#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
grep -Fq -- '--mode major-compatible' "$ROOT/kernel-lab.sh"
grep -Fq 'ubuntu|debian)' "$ROOT/kernel-lab.sh"
grep -Fq 'module compile/load validation remains mandatory' "$ROOT/kernel-lab.sh"
echo 'PASS: APT distro kernels use an explicit same-major GCC fallback behind runtime module validation'
