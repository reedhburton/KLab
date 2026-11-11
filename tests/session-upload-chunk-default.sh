#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq "chunk_size = int(os.environ.get('KLAB_SERIAL_UPLOAD_CHUNK', '96'))" "$ROOT/kernel-lab.sh" || {
  echo 'FAIL: serial upload default is not the broad-matrix-validated 96-byte size' >&2
  exit 1
}
echo 'session serial upload default: PASS'
