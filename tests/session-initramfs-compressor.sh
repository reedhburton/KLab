#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
f="$ROOT/kernel-lab.sh"
grep -Fq 'if have pigz; then pigz -1; else gzip -1; fi' "$f" || { echo 'FAIL: parallel initramfs compression lacks gzip fallback' >&2; exit 1; }
grep -Fq '| compress_session_initramfs) > "$image"' "$f" || { echo 'FAIL: session initramfs does not use compressor helper' >&2; exit 1; }
echo 'session initramfs compressor: PASS'
