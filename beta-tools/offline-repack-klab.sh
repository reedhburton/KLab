#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
[[ $# -ge 2 && $# -le 4 ]] || { echo "usage: $0 TARGET OUTPUT.klab [OFFLINE_ROOT] [ARCH]" >&2; exit 2; }
target="$1"; output="$2"; root="${3:-$HOME/.local/share/klab-beta/offline}"; arch="${4:-x86_64}"
export KLAB_ROOT="$root" KLAB_HOME="$root" KLAB_COMPAT_LINKS=0 KLAB_OFFLINE=1 KLAB_ARCH="$arch"
case "$arch" in mips|mipsel|mips64|mips64el) export KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 KLAB_ENABLE_EXPERIMENTAL_E2E=1 ;; esac
info="$("$SELF/klab" info "$target")"
build="$(printf '%s\n' "$info" | sed -n 's/^Build tree:[[:space:]]*//p' | head -n1)"
bundle_dir="$(printf '%s\n' "$info" | sed -n 's/^Kernel image:[[:space:]]*//p' | head -n1)"
bundle_dir="${bundle_dir%/*}"
if [[ ! -f "$bundle_dir/bundle.env" && -n "$build" ]]; then
  probe="$build"
  while [[ "$probe" != / && ! -f "$probe/bundle.env" ]]; do probe="${probe%/*}"; [[ -n "$probe" ]] || probe=/; done
  [[ -f "$probe/bundle.env" ]] && bundle_dir="$probe"
fi
[[ -n "$bundle_dir" && -f "$bundle_dir/bundle.env" ]] || { echo "offline repack cannot locate imported metadata for $target/$arch" >&2; exit 3; }
# shellcheck disable=SC1090
source "$bundle_dir/bundle.env"
userspace="${BUNDLE_GUEST_USERSPACE_SPEC:-busybox-static}"
if [[ "$userspace" == busybox-static && ! -x "$root/artifacts/userspaces/busybox/$arch/busybox" ]]; then
  buildroot="$root/artifacts/userspaces/buildroot/${KLAB_BUILDROOT_VERSION:-2025.02.18}/minimal/$arch"
  [[ -f "$buildroot/rootfs.tar" ]] || { echo "offline repack has no guest userspace for $target/$arch" >&2; exit 4; }
  userspace=buildroot:minimal
fi
args=(--userspace "$userspace")
case "$userspace" in buildroot:*) args+=(--include-sdk) ;; esac
if [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 && -d "${BUNDLE_TOOLCHAIN_DIR:-}" ]]; then
  args+=(--include-toolchain "$BUNDLE_TOOLCHAIN_DIR" --toolchain-id "$BUNDLE_TOOLCHAIN_ID" --toolchain-cc "$BUNDLE_TOOLCHAIN_CC_REL")
fi
"$SELF/klab-bundle.sh" create "$target" -o "$output" "${args[@]}"
"$SELF/klab" verify "$output"
