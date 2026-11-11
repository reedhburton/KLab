#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/kernel-lab.sh"
grep -Fq "os.environ.get('KLAB_SERIAL_UPLOAD_CHUNK', '96')" "$f" || { echo 'FAIL: broad-matrix-safe 96-byte default missing' >&2; exit 1; }
grep -Fq "chunk_size < 12 or chunk_size > 384" "$f" || { echo 'FAIL: upload frame option is unbounded' >&2; exit 1; }
echo 'PASS: serial upload frames are opt-in configurable with a broad-matrix-validated default'
