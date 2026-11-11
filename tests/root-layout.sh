#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(mktemp -d)"; trap 'rm -rf "$ROOT"' EXIT
BASE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

# R25 default: native canonical tree, no legacy compatibility links.
export KLAB_ROOT="$ROOT/lab"
unset KLAB_HOME KLAB_COMPAT_LINKS
source "$BASE/lib/klab-root.sh"
klab_root_ensure_layout

for p in bin config artifacts/kernels artifacts/buildenvs artifacts/toolchains artifacts/distro-toolchains artifacts/userspaces artifacts/sources targets/kernels cache/linux cache/sources work/builds work/initramfs work/jobs work/sessions work/buildroot work/buildroot-cache transfer/exports results/logs results/crashes state/examples; do
  [[ -d "$KLAB_ROOT/$p" ]] || { echo "missing $p" >&2; exit 1; }
done
for p in linux sources builds initramfs jobs sessions buildroot logs crashes exports kernels toolchains guests buildenvs distro-toolchains userspaces MODE; do
  [[ ! -e "$KLAB_ROOT/$p" && ! -L "$KLAB_ROOT/$p" ]] || { echo "default unexpectedly created compat path $p" >&2; exit 1; }
done
[[ "$KLAB_HOME" == "$KLAB_ROOT" ]]
[[ "$KLAB_BUILDROOT_CACHE_HOME" == "$KLAB_ROOT/work/buildroot-cache" ]]
[[ "$KLAB_COMPAT_LINKS" == 0 ]]

# Explicit opt-in still creates the legacy view, including MODE.
compat="$ROOT/compat"
KLAB_ROOT="$compat" KLAB_HOME= KLAB_COMPAT_LINKS=1 "$BASE/klab-root" init >/dev/null
[[ ! -d "$compat/state/MODE" ]]
printf "offline\n" > "$compat/MODE"
[[ "$(cat "$compat/state/MODE")" == offline ]]
for p in linux sources builds initramfs jobs sessions buildroot logs crashes exports kernels toolchains guests buildenvs distro-toolchains userspaces MODE; do
  [[ -L "$compat/$p" ]] || { echo "missing opt-in compat symlink $p" >&2; exit 1; }
done
KLAB_ROOT="$compat" KLAB_HOME= KLAB_COMPAT_LINKS=1 "$BASE/klab-root" doctor >/dev/null

# Default/native doctor sees old managed links as leftovers but remains usable.
out="$(KLAB_ROOT="$compat" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$BASE/klab-root" doctor)"
grep -q 'run prune-compat' <<<"$out"

# prune-compat removes only expected managed links.
KLAB_ROOT="$compat" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$BASE/klab-root" prune-compat >/dev/null
for p in linux sources builds initramfs jobs sessions buildroot logs crashes exports kernels toolchains guests buildenvs distro-toolchains userspaces MODE; do
  [[ ! -e "$compat/$p" && ! -L "$compat/$p" ]] || { echo "prune left compat path $p" >&2; exit 1; }
done
[[ -d "$compat/work/builds" && -d "$compat/artifacts/toolchains" ]]

# prune-compat refuses foreign symlinks rather than deleting them.
foreign="$ROOT/foreign"
KLAB_ROOT="$foreign" KLAB_HOME= KLAB_COMPAT_LINKS=1 "$BASE/klab-root" init >/dev/null
rm "$foreign/builds"; ln -s /tmp "$foreign/builds"
if KLAB_ROOT="$foreign" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$BASE/klab-root" prune-compat >/dev/null 2>&1; then
  echo 'foreign compatibility link was removed/accepted' >&2; exit 1
fi
[[ -L "$foreign/builds" && "$(readlink "$foreign/builds")" == /tmp ]]
# Validation is atomic: a good managed link remains when any link is foreign.
[[ -L "$foreign/logs" ]]

# A real legacy directory is refused before any managed link is pruned.
real="$ROOT/real"
KLAB_ROOT="$real" KLAB_HOME= KLAB_COMPAT_LINKS=1 "$BASE/klab-root" init >/dev/null
rm "$real/builds"; mkdir "$real/builds"; echo keep > "$real/builds/sentinel"
if KLAB_ROOT="$real" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$BASE/klab-root" prune-compat >/dev/null 2>&1; then
  echo 'real legacy directory was accepted for pruning' >&2; exit 1
fi
[[ -f "$real/builds/sentinel" && -L "$real/logs" ]]

# Separate-root migration preserves known and unknown files and does not create
# compatibility links by default.
old="$ROOT/old"; mkdir -p "$old/builds" "$old/logs"; echo x > "$old/builds/a"; echo y > "$old/unknown-file"
KLAB_ROOT="$ROOT/new" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$BASE/klab-root" migrate "$old" >/dev/null
[[ -f "$ROOT/new/work/builds/a" ]]
[[ -f "$ROOT/new/state/legacy-unclassified/unknown-file" ]]
[[ ! -e "$ROOT/new/builds" && ! -L "$ROOT/new/builds" ]]

# Existing roots can be normalized in place without recreating legacy paths.
inplace="$ROOT/inplace"; mkdir -p "$inplace/builds" "$inplace/logs"; echo z > "$inplace/builds/b"
KLAB_ROOT="$inplace" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$BASE/klab-root" normalize >/dev/null
[[ -f "$inplace/work/builds/b" ]]
[[ ! -e "$inplace/builds" && ! -L "$inplace/builds" ]]
[[ ! -e "$inplace/logs" && ! -L "$inplace/logs" ]]

# Conflicting legacy and new roots are rejected.
if KLAB_ROOT="$ROOT/a" KLAB_HOME="$ROOT/b" bash -c 'source "$1"' _ "$BASE/lib/klab-root.sh" >/dev/null 2>&1; then
  echo 'conflicting roots were accepted' >&2; exit 1
fi

echo 'PASS root-layout'
