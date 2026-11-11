#!/usr/bin/env bash
set -Eeuo pipefail
BASE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
SRC="$FIX/src"; LAB="$FIX/lab"; mkdir -p "$SRC"

cp -a "$BASE/lib" "$BASE/providers" "$SRC/"
cp "$BASE"/kernel-lab.sh "$SRC/kernel-lab.sh"
cp "$BASE"/klab-bundle.sh "$SRC/klab-bundle.sh"
cp "$BASE"/klab-buildroot-cache.sh "$SRC/klab-buildroot-cache.sh"
cat > "$SRC/klab-buildenv.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
STORE="$KLAB_HOME/buildenvs"
TC="$KLAB_HOME/toolchains"
DT="$KLAB_HOME/distro-toolchains"
printf '%s\n' "$STORE" "$TC" "$DT"
EOS
cat > "$SRC/klab-distro-toolchain.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
STORE="${KLAB_HOME}/distro-toolchains"
WORK="${KLAB_HOME}/buildroot/native-capture"
printf '%s\n' "$STORE" "$WORK"
EOS
chmod +x "$SRC"/*.sh

"$BASE/apply-root-layout.sh" "$SRC" >/dev/null
"$BASE/apply-root-layout.sh" "$SRC" >/dev/null

for f in kernel-lab.sh klab-bundle.sh klab-buildroot-cache.sh klab-buildenv.sh klab-distro-toolchain.sh; do
  [[ "$(grep -c KLAB_NATIVE_PATHS_R23 "$SRC/$f")" -eq 1 ]] || { echo "bad R23 marker count in $f" >&2; exit 1; }
  bash -n "$SRC/$f"
done

# First-party variables must resolve directly to canonical buckets.
grep -q '^BUILDS="\$KLAB_WORK/builds"$' "$SRC/kernel-lab.sh"
grep -q '^LOGS="\$KLAB_RESULTS/logs"$' "$SRC/kernel-lab.sh"
grep -q '^KERNELS="\$KLAB_TARGETS/kernels"$' "$SRC/kernel-lab.sh"
grep -q '^TOOLCHAINS="\$KLAB_TOOLCHAIN_STORE"$' "$SRC/kernel-lab.sh"
grep -q '^EXPORTS="\$KLAB_TRANSFER/exports"$' "$SRC/kernel-lab.sh"
grep -q '^MODE_FILE="\$KLAB_STATE/MODE"$' "$SRC/kernel-lab.sh"
grep -q '^SRC="\$KLAB_CACHE/linux"$' "$SRC/klab-bundle.sh"
grep -q '^GUESTS="\$KLAB_USERSPACE_STORE"$' "$SRC/klab-bundle.sh"
grep -q '^STORE="\$KLAB_BUILDENV_STORE"$' "$SRC/klab-buildenv.sh"
grep -q '^TC="\$KLAB_TOOLCHAIN_STORE"$' "$SRC/klab-buildenv.sh"
grep -q '^DT="\$KLAB_DISTRO_TOOLCHAIN_STORE"$' "$SRC/klab-buildenv.sh"
grep -q '^STORE="\$KLAB_DISTRO_TOOLCHAIN_STORE"$' "$SRC/klab-distro-toolchain.sh"
grep -q '^WORK="\$KLAB_WORK/buildroot/native-capture"$' "$SRC/klab-distro-toolchain.sh"

# Prove the retained runner no longer needs compatibility symlinks just to load
# and inspect its state.
out="$(KLAB_ROOT="$LAB" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$SRC/kernel-lab.sh" status)"
grep -q "Home:.*$LAB" <<<"$out"
[[ ! -e "$LAB/builds" && ! -L "$LAB/builds" ]]
[[ -d "$LAB/work/builds" ]]
[[ -d "$LAB/results" ]]

# Buildroot helper stays contained by the canonical KLAB_WORK-derived override.
out="$(KLAB_ROOT="$LAB" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$SRC/klab-buildroot-cache.sh" status || true)"
grep -q "Work root:.*$LAB/work/buildroot-cache" <<<"$out"
KLAB_ROOT="$LAB" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$SRC/klab-root" doctor >/dev/null

echo 'PASS native-paths'
