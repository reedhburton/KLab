#!/usr/bin/env bash
set -Eeuo pipefail
BASE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
SRC="$FIX/src"; LAB="$FIX/lab"; mkdir -p "$SRC"
cp -a "$BASE/lib" "$BASE/providers" "$SRC/"
cp "$BASE"/kernel-lab.sh "$SRC/kernel-lab.sh"
cp "$BASE"/klab-bundle.sh "$SRC/klab-bundle.sh"
cp "$BASE"/klab-buildroot-cache.sh "$SRC/klab-buildroot-cache.sh"
chmod +x "$SRC"/*.sh
"$BASE/apply-root-layout.sh" "$SRC" >/dev/null

# No KLAB_COMPAT_LINKS setting: this is the R25 policy under test.
KLAB_ROOT="$LAB" KLAB_HOME= "$SRC/klab-root" init >/dev/null
[[ -d "$LAB/work/builds" && -d "$LAB/results/logs" && -d "$LAB/artifacts/toolchains" ]]
for p in builds logs kernels toolchains exports buildroot MODE; do
  [[ ! -e "$LAB/$p" && ! -L "$LAB/$p" ]] || { echo "default created legacy path $p" >&2; exit 1; }
done
KLAB_ROOT="$LAB" KLAB_HOME= "$SRC/kernel-lab.sh" status >/dev/null
KLAB_ROOT="$LAB" KLAB_HOME= "$SRC/klab-buildroot-cache.sh" status >/dev/null || true
for p in builds logs kernels toolchains exports buildroot MODE; do
  [[ ! -e "$LAB/$p" && ! -L "$LAB/$p" ]] || { echo "first-party command created legacy path $p" >&2; exit 1; }
done

# Opt-in is explicit and reversible.
KLAB_ROOT="$LAB" KLAB_HOME= KLAB_COMPAT_LINKS=1 "$SRC/klab-root" init >/dev/null
[[ -L "$LAB/builds" && -L "$LAB/logs" && -L "$LAB/MODE" ]]
KLAB_ROOT="$LAB" KLAB_HOME= "$SRC/klab-root" prune-compat >/dev/null
[[ ! -e "$LAB/builds" && ! -L "$LAB/builds" ]]
[[ ! -e "$LAB/MODE" && ! -L "$LAB/MODE" ]]

echo 'PASS compat-default-off'
