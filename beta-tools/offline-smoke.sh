#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
[[ $# -ge 1 && $# -le 3 ]] || { echo "usage: $0 TARGET [OFFLINE_ROOT] [ARCH]" >&2; exit 2; }
root="${2:-$HOME/.local/share/klab-beta/offline}"; arch="${3:-x86_64}"
export KLAB_ROOT="$root" KLAB_HOME="$root" KLAB_COMPAT_LINKS=0 KLAB_OFFLINE=1
case "$arch" in mips|mipsel|mips64|mips64el) export KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 KLAB_ENABLE_EXPERIMENTAL_E2E=1 ;; esac
"$SELF/klab" smoke "$1" --arch "$arch"
