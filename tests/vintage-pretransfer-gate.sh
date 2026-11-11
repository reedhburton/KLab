#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
f="$ROOT/lib/buildenv-capture.sh"
grep -q 'KLAB_ALLOW_UNPROVEN_VINTAGE_RELOCS' "$f"
grep -q -- '--strict-vintage' "$f"
grep -q 'sealed toolchain emits relocation semantics not proven compatible' "$f"
echo 'PASS: buildenv/toolchain pair validation gates unproven vintage relocation semantics before transfer'
