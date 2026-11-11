#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
[[ $# -ge 2 && $# -le 4 ]] || { echo "usage: $0 TARGET MODULE_DIR [OUTPUT_DIR] [OFFLINE_ROOT]" >&2; exit 2; }
target="$1"; module="$(cd "$2" && pwd)"; out="${3:-$PWD/klab-module-output}"; root="${4:-$HOME/.local/share/klab-beta/offline}"
mkdir -p "$out"; out="$(cd "$out" && pwd)"; export KLAB_ROOT="$root" KLAB_HOME="$root" KLAB_COMPAT_LINKS=0
"$SELF/klab" build-module "$target" --arch x86_64 --module "$module" -o "$out"
echo "Offline module output: $out"
