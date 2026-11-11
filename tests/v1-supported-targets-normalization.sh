#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
! grep -R -Fq 'v5.10__i386' "$ROOT/SUPPORTED-TARGETS.tsv" "$ROOT/SUPPORTED-TARGETS-MATRIX.md"
grep -Fq $'built\tupstream:v5.10\tlinux\ti386\tv5.10\tbuilt' "$ROOT/SUPPORTED-TARGETS.tsv"
grep -Fq '| i386 | v5.10 |' "$ROOT/SUPPORTED-TARGETS-MATRIX.md"
echo 'PASS: V1 support catalog uses canonical target plus explicit i386 architecture'
