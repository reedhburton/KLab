#!/usr/bin/env bash
# KLab unified-root path contract.
# Public contract: KLAB_ROOT is the only path variable a normal user should set.
# R25: first-party helpers use canonical directories directly; compatibility
# symlinks are opt-in and exist only for older/external scripts.
# KLAB_COMPAT_DEFAULT_OFF_R25

if [[ -n "${KLAB_ROOT_LIB_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
KLAB_ROOT_LIB_LOADED=1

klab_root_die() { printf 'klab-root: ERROR: %s\n' "$*" >&2; return 1; }

klab_root_resolve() {
  local root="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}"
  [[ -n "$root" ]] || { klab_root_die 'empty KLAB_ROOT'; return 1; }
  case "$root" in
    /*) ;;
    *) root="$PWD/$root" ;;
  esac
  root="$(python3 - "$root" <<'PY'
import os,sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)" || return 1
  [[ "$root" != / ]] || { klab_root_die 'KLAB_ROOT may not be /'; return 1; }
  [[ "$root" != *$'\n'* && "$root" != *$'\r'* ]] || { klab_root_die 'KLAB_ROOT contains a newline'; return 1; }
  printf '%s\n' "$root"
}

KLAB_ROOT="$(klab_root_resolve)" || { return 1 2>/dev/null || exit 1; }
export KLAB_ROOT

# KLAB_HOME is retained as an alias only. A conflicting value means the process
# has two roots, which defeats containment and is rejected.
if [[ -n "${KLAB_HOME:-}" ]]; then
  _kh="$(python3 - "$KLAB_HOME" <<'PY'
import os,sys
print(os.path.abspath(os.path.expanduser(sys.argv[1])))
PY
)"
  [[ "$_kh" == "$KLAB_ROOT" ]] || {
    klab_root_die "KLAB_HOME ($_kh) conflicts with KLAB_ROOT ($KLAB_ROOT); set only KLAB_ROOT"
    return 1 2>/dev/null || exit 1
  }
fi
KLAB_HOME="$KLAB_ROOT"
export KLAB_HOME

# Canonical stable directories.
export KLAB_BIN="$KLAB_ROOT/bin"
export KLAB_CONFIG="$KLAB_ROOT/config"
export KLAB_ARTIFACTS="$KLAB_ROOT/artifacts"
export KLAB_ARTIFACT_KERNELS="$KLAB_ARTIFACTS/kernels"
export KLAB_BUILDENV_STORE="$KLAB_ARTIFACTS/buildenvs"
export KLAB_TOOLCHAIN_STORE="$KLAB_ARTIFACTS/toolchains"
export KLAB_DISTRO_TOOLCHAIN_STORE="$KLAB_ARTIFACTS/distro-toolchains"
export KLAB_USERSPACE_STORE="$KLAB_ARTIFACTS/userspaces"
export KLAB_SOURCE_ARTIFACT_STORE="$KLAB_ARTIFACTS/sources"
export KLAB_TARGETS="$KLAB_ROOT/targets"
export KLAB_CACHE="$KLAB_ROOT/cache"
export KLAB_WORK="$KLAB_ROOT/work"
export KLAB_TRANSFER="$KLAB_ROOT/transfer"
export KLAB_RESULTS="$KLAB_ROOT/results"
export KLAB_STATE="$KLAB_ROOT/state"
export KLAB_SUITES="$KLAB_ROOT/suites"

# Legacy helper override, now derived from the root so it cannot escape the tree.
export KLAB_BUILDROOT_CACHE_HOME="$KLAB_WORK/buildroot-cache"
export KLAB_COMPAT_LINKS="${KLAB_COMPAT_LINKS:-0}"
case "$KLAB_COMPAT_LINKS" in 0|1) ;; *) klab_root_die "KLAB_COMPAT_LINKS must be 0 or 1"; return 1 2>/dev/null || exit 1 ;; esac

klab_root_mkdirs() {
  mkdir -p \
    "$KLAB_BIN" "$KLAB_CONFIG" \
    "$KLAB_ARTIFACT_KERNELS" "$KLAB_BUILDENV_STORE" "$KLAB_TOOLCHAIN_STORE" \
    "$KLAB_DISTRO_TOOLCHAIN_STORE" "$KLAB_USERSPACE_STORE" "$KLAB_SOURCE_ARTIFACT_STORE" \
    "$KLAB_TARGETS/kernels" \
    "$KLAB_CACHE/linux" "$KLAB_CACHE/sources" \
    "$KLAB_WORK/builds" "$KLAB_WORK/initramfs" "$KLAB_WORK/jobs" "$KLAB_WORK/sessions" \
    "$KLAB_WORK/buildroot" "$KLAB_WORK/buildroot-cache" \
    "$KLAB_TRANSFER/exports" \
    "$KLAB_RESULTS/logs" "$KLAB_RESULTS/crashes" \
    "$KLAB_STATE/examples" "$KLAB_SUITES"
}

klab_root_link_one() {
  local legacy="$1" canonical="$2"
  [[ "$legacy" != "$canonical" ]] || return 0
  if [[ -L "$legacy" ]]; then
    local current
    current="$(readlink "$legacy")"
    [[ "$current" == "$canonical" ]] && return 0
    klab_root_die "legacy path $legacy already points to $current (wanted $canonical)"
    return 1
  fi
  if [[ -e "$legacy" ]]; then
    # Never hide existing data. `klab-root normalize` performs the move.
    return 0
  fi
  if [[ "${3:-directory}" == file ]]; then
    mkdir -p "$(dirname "$canonical")" "$(dirname "$legacy")"
  else
    mkdir -p "$canonical" "$(dirname "$legacy")"
  fi
  ln -s "$canonical" "$legacy"
}

klab_root_compat_links() {
  klab_root_link_one "$KLAB_ROOT/linux"      "$KLAB_CACHE/linux"
  klab_root_link_one "$KLAB_ROOT/sources"    "$KLAB_CACHE/sources"
  klab_root_link_one "$KLAB_ROOT/builds"     "$KLAB_WORK/builds"
  klab_root_link_one "$KLAB_ROOT/initramfs"  "$KLAB_WORK/initramfs"
  klab_root_link_one "$KLAB_ROOT/jobs"       "$KLAB_WORK/jobs"
  klab_root_link_one "$KLAB_ROOT/sessions"   "$KLAB_WORK/sessions"
  klab_root_link_one "$KLAB_ROOT/buildroot"  "$KLAB_WORK/buildroot"
  klab_root_link_one "$KLAB_ROOT/logs"       "$KLAB_RESULTS/logs"
  klab_root_link_one "$KLAB_ROOT/crashes"    "$KLAB_RESULTS/crashes"
  klab_root_link_one "$KLAB_ROOT/exports"    "$KLAB_TRANSFER/exports"
  klab_root_link_one "$KLAB_ROOT/kernels"    "$KLAB_TARGETS/kernels"
  klab_root_link_one "$KLAB_ROOT/toolchains" "$KLAB_TOOLCHAIN_STORE"
  klab_root_link_one "$KLAB_ROOT/guests"     "$KLAB_USERSPACE_STORE"
  # M2/R12+ direct-store spellings.
  klab_root_link_one "$KLAB_ROOT/buildenvs"         "$KLAB_BUILDENV_STORE"
  klab_root_link_one "$KLAB_ROOT/distro-toolchains" "$KLAB_DISTRO_TOOLCHAIN_STORE"
  klab_root_link_one "$KLAB_ROOT/userspaces"        "$KLAB_USERSPACE_STORE"
  klab_root_link_one "$KLAB_ROOT/MODE"              "$KLAB_STATE/MODE" file
}

klab_root_check_unlink_one() {
  local legacy="$1" canonical="$2" current
  [[ -e "$legacy" || -L "$legacy" ]] || return 0
  if [[ ! -L "$legacy" ]]; then
    klab_root_die "refusing to remove real legacy path $legacy; run normalize or move it manually"
    return 1
  fi
  current="$(readlink "$legacy")"
  if [[ "$current" != "$canonical" ]]; then
    klab_root_die "refusing foreign compatibility link $legacy -> $current (expected $canonical)"
    return 1
  fi
}

klab_root_unlink_one() {
  local legacy="$1" canonical="$2"
  [[ -e "$legacy" || -L "$legacy" ]] || return 0
  rm -- "$legacy"
  printf 'removed compat: %s -> %s\n' "$legacy" "$canonical"
}

klab_root_prune_compat_links() {
  # Validate the complete set first so a foreign link or real legacy directory
  # cannot cause a partially-pruned compatibility view.
  local rc=0
  klab_root_check_unlink_one "$KLAB_ROOT/linux"      "$KLAB_CACHE/linux" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/sources"    "$KLAB_CACHE/sources" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/builds"     "$KLAB_WORK/builds" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/initramfs"  "$KLAB_WORK/initramfs" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/jobs"       "$KLAB_WORK/jobs" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/sessions"   "$KLAB_WORK/sessions" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/buildroot"  "$KLAB_WORK/buildroot" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/logs"       "$KLAB_RESULTS/logs" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/crashes"    "$KLAB_RESULTS/crashes" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/exports"    "$KLAB_TRANSFER/exports" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/kernels"    "$KLAB_TARGETS/kernels" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/toolchains" "$KLAB_TOOLCHAIN_STORE" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/guests"     "$KLAB_USERSPACE_STORE" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/buildenvs"         "$KLAB_BUILDENV_STORE" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/distro-toolchains" "$KLAB_DISTRO_TOOLCHAIN_STORE" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/userspaces"        "$KLAB_USERSPACE_STORE" || rc=1
  klab_root_check_unlink_one "$KLAB_ROOT/MODE"              "$KLAB_STATE/MODE" || rc=1
  (( rc == 0 )) || return "$rc"

  klab_root_unlink_one "$KLAB_ROOT/linux"      "$KLAB_CACHE/linux"
  klab_root_unlink_one "$KLAB_ROOT/sources"    "$KLAB_CACHE/sources"
  klab_root_unlink_one "$KLAB_ROOT/builds"     "$KLAB_WORK/builds"
  klab_root_unlink_one "$KLAB_ROOT/initramfs"  "$KLAB_WORK/initramfs"
  klab_root_unlink_one "$KLAB_ROOT/jobs"       "$KLAB_WORK/jobs"
  klab_root_unlink_one "$KLAB_ROOT/sessions"   "$KLAB_WORK/sessions"
  klab_root_unlink_one "$KLAB_ROOT/buildroot"  "$KLAB_WORK/buildroot"
  klab_root_unlink_one "$KLAB_ROOT/logs"       "$KLAB_RESULTS/logs"
  klab_root_unlink_one "$KLAB_ROOT/crashes"    "$KLAB_RESULTS/crashes"
  klab_root_unlink_one "$KLAB_ROOT/exports"    "$KLAB_TRANSFER/exports"
  klab_root_unlink_one "$KLAB_ROOT/kernels"    "$KLAB_TARGETS/kernels"
  klab_root_unlink_one "$KLAB_ROOT/toolchains" "$KLAB_TOOLCHAIN_STORE"
  klab_root_unlink_one "$KLAB_ROOT/guests"     "$KLAB_USERSPACE_STORE"
  klab_root_unlink_one "$KLAB_ROOT/buildenvs"         "$KLAB_BUILDENV_STORE"
  klab_root_unlink_one "$KLAB_ROOT/distro-toolchains" "$KLAB_DISTRO_TOOLCHAIN_STORE"
  klab_root_unlink_one "$KLAB_ROOT/userspaces"        "$KLAB_USERSPACE_STORE"
  klab_root_unlink_one "$KLAB_ROOT/MODE"              "$KLAB_STATE/MODE"
}

klab_root_ensure_layout() {
  local marker="$KLAB_STATE/.layout-v1"
  if [[ ! -f "$marker" ]]; then
    klab_root_mkdirs || return 1
    : > "$marker" || return 1
  fi
  [[ "$KLAB_COMPAT_LINKS" == 0 ]] || klab_root_compat_links || return 1
}

unset _kh
