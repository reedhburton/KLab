#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
[[ $# -ge 2 && $# -le 3 ]] || { echo "usage: $0 TARGET TRANSFER_DIR [KLAB_ROOT]" >&2; exit 2; }
target="$1"; transfer="$(mkdir -p "$2" && cd "$2" && pwd)"; root="${3:-$HOME/.local/share/klab-beta/staging}"
mkdir -p "$root"; export KLAB_ROOT="$root" KLAB_HOME="$root" KLAB_COMPAT_LINKS=0
"$SELF/klab" init --staging >/dev/null
safe="$(printf '%s' "$target" | tr ':@/' '___')"; args=()
case "$target" in upstream:*) ;; *) args+=(--distro-toolchain);; esac
"$SELF/klab" prepare "$target" --arch x86_64 "${args[@]}" -o "$transfer/$safe.klab"
"$SELF/klab" verify "$transfer/$safe.klab"
echo "Created verified transfer set in $transfer"
