#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/kernel-lab.sh"
grep -Fq "s.settimeout(float(os.environ.get('KLAB_UPLOAD_ACK_TIMEOUT', '15')))" "$f" || { echo 'FAIL: upload acknowledgement read remains unbounded' >&2; exit 1; }
grep -Fq 'for attempt in 1 2 3; do' "$f" || { echo 'FAIL: whole-file upload retry loop missing' >&2; exit 1; }
grep -Fq 'Upload acknowledgement failed; retrying whole file' "$f" || { echo 'FAIL: upload retry is not auditable' >&2; exit 1; }
grep -Fq 'upload failed after 3 attempts' "$f" || { echo 'FAIL: bounded upload failure missing' >&2; exit 1; }
echo 'PASS: serial uploads have bounded ACK waits and safe whole-file retries'
