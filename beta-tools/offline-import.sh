#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
[[ $# -ge 1 && $# -le 2 ]] || { echo "usage: $0 TRANSFER_DIR [OFFLINE_ROOT]" >&2; exit 2; }
transfer="$(cd "$1" && pwd)"; root="${2:-$HOME/.local/share/klab-beta/offline}"
for f in "$transfer"/*.klabdistrotoolchain; do [[ ! -e "$f" ]] || "$SELF/klab-distro-toolchain.sh" verify "$f"; done
for f in "$transfer"/*.klabbuildenv; do [[ ! -e "$f" ]] || "$SELF/klab-buildenv.sh" verify "$f" --deep; done
for f in "$transfer"/*.klab; do [[ ! -e "$f" ]] || "$SELF/klab" verify "$f"; done
mkdir -p "$root"; export KLAB_ROOT="$root" KLAB_HOME="$root" KLAB_COMPAT_LINKS=0
"$SELF/klab" init --offline >/dev/null
"$SELF/klab" import "$transfer"
echo "Imported verified transfer repository into $root"
"$SELF/klab" targets
