#!/usr/bin/env bash
set -Eeuo pipefail

# KLAB_UNIFIED_ROOT_R22
# KLAB_NATIVE_PATHS_R23
# KLAB_RESIDUAL_PATH_AUDIT_R24
_KLAB_SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [[ -f "$_KLAB_SELF_DIR/lib/klab-root.sh" ]]; then
  # shellcheck source=lib/klab-root.sh
  source "$_KLAB_SELF_DIR/lib/klab-root.sh"
  klab_root_ensure_layout
fi
unset _KLAB_SELF_DIR
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec python3 "$SELF_DIR/lib/klab_distro_toolchain.py" "$@"
