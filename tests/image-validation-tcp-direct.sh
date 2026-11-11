#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq 'build-user "$target"' "$ROOT/klab-image-tcp-gate.sh"
grep -Fq -- '--net-bus "$bus"' "$ROOT/klab-image-tcp-gate.sh"
grep -Fq 'CLIENT_RX ACK:klab-image-validation' "$ROOT/klab-image-tcp-gate.sh"
! grep -Fq 'multiguest-run' "$ROOT/klab-image-validate.sh"
grep -Fq 'klab-image-tcp-gate.sh' "$ROOT/klab-image-validate.sh"
echo 'image validation TCP gate reuses installed bundle directly: PASS'
