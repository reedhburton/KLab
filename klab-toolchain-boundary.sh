#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec python3 "$SELF_DIR/lib/toolchain_boundary.py" "$@"
