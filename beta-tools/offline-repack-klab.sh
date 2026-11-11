#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
[[ $# -ge 2 && $# -le 4 ]] || { echo "usage: $0 TARGET OUTPUT.klab [OFFLINE_ROOT] [ARCH]" >&2; exit 2; }
target="$1"; output="$2"; root="${3:-$HOME/.local/share/klab-beta/offline}"; arch="${4:-x86_64}"
export KLAB_ROOT="$root" KLAB_HOME="$root" KLAB_COMPAT_LINKS=0 KLAB_OFFLINE=1 KLAB_ARCH="$arch"
case "$arch" in mips|mipsel|mips64|mips64el) export KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 KLAB_ENABLE_EXPERIMENTAL_E2E=1 ;; esac
info="$("$SELF/klab" info "$target")"
build="$(printf '%s\n' "$info" | sed -n 's/^Build tree:[[:space:]]*//p' | head -n1)"
[[ -n "$build" && -f "$(dirname "$build")/bundle.env" ]] || { echo "offline repack cannot locate imported metadata for $target/$arch" >&2; exit 3; }
# shellcheck disable=SC1090
source "$(dirname "$build")/bundle.env"
args=(--userspace "${BUNDLE_GUEST_USERSPACE_SPEC:-busybox-static}")
case "${BUNDLE_GUEST_USERSPACE_SPEC:-}" in buildroot:*) args+=(--include-sdk) ;; esac
if [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 && -d "${BUNDLE_TOOLCHAIN_DIR:-}" ]]; then
  args+=(--include-toolchain "$BUNDLE_TOOLCHAIN_DIR" --toolchain-id "$BUNDLE_TOOLCHAIN_ID" --toolchain-cc "$BUNDLE_TOOLCHAIN_CC_REL")
fi
"$SELF/klab-bundle.sh" create "$target" -o "$output" "${args[@]}"
"$SELF/klab" verify "$output"
