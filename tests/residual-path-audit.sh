#!/usr/bin/env bash
set -Eeuo pipefail
BASE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FIX="$(mktemp -d)"; trap 'rm -rf "$FIX"' EXIT
SRC="$FIX/src"; LAB="$FIX/lab"; mkdir -p "$SRC"

cp -a "$BASE/lib" "$BASE/providers" "$SRC/"
cp "$BASE"/kernel-lab.sh "$SRC/kernel-lab.sh"
cp "$BASE"/klab-bundle.sh "$SRC/klab-bundle.sh"
cp "$BASE"/klab-buildroot-cache.sh "$SRC/klab-buildroot-cache.sh"

# Exercise newer-helper spellings, including nested fallback forms that R23 did
# not catch.
cat > "$SRC/klab-buildenv.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
STORE="$KLAB_HOME/buildenvs"
TC="${KLAB_HOME}/toolchains"
printf '%s\n' "$STORE" "$TC"
EOS
cat > "$SRC/klab-distro-toolchain.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
STORE="${KLAB_HOME}/distro-toolchains"
WORK="$KLAB_HOME/buildroot/native-capture"
printf '%s\n' "$STORE" "$WORK"
EOS
chmod +x "$SRC"/*.sh

out="$($BASE/apply-root-layout.sh "$SRC")"
grep -q 'Residual-path audit: PASS' <<<"$out"
# Idempotence: the audit marker should not multiply.
out="$($BASE/apply-root-layout.sh "$SRC")"
grep -q 'Residual-path audit: PASS' <<<"$out"
for f in kernel-lab.sh klab-bundle.sh klab-buildroot-cache.sh klab-buildenv.sh klab-distro-toolchain.sh; do
  [[ "$(grep -c KLAB_RESIDUAL_PATH_AUDIT_R24 "$SRC/$f")" -eq 1 ]] || { echo "bad R24 marker count in $f" >&2; exit 1; }
  bash -n "$SRC/$f"
done

# Buildroot install ownership must be canonical even with compatibility links off.
grep -Fq 'dest="${KLAB_BUILDROOT_DEST:-$KLAB_WORK/buildroot}"' "$SRC/klab-buildroot-cache.sh"
grep -Fq 'KLAB_ROOT=/srv/kernel-lab' "$SRC/klab-buildroot-cache.sh"
grep -Fq '/srv/kernel-lab/work/buildroot/dl' "$SRC/klab-buildroot-cache.sh"
! grep -Fq '<KLAB_HOME>/buildroot' "$SRC/klab-buildroot-cache.sh"

# Public help uses KLAB_ROOT; KLAB_HOME may remain only as a propagated alias on
# lines that also explicitly set KLAB_ROOT.
help="$(KLAB_ROOT="$LAB" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$SRC/kernel-lab.sh" --help 2>&1 || true)"
grep -q 'KLAB_ROOT' <<<"$help"
! grep -q 'KLAB_HOME,' <<<"$help"
help="$(KLAB_ROOT="$LAB" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$SRC/klab-bundle.sh" --help 2>&1 || true)"
grep -q 'KLAB_ROOT' <<<"$help"
! grep -q 'KLAB_HOME,' <<<"$help"

# The first-party runtime must not create legacy top-level directories in native mode.
KLAB_ROOT="$LAB" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$SRC/kernel-lab.sh" status >/dev/null
KLAB_ROOT="$LAB" KLAB_HOME= KLAB_COMPAT_LINKS=0 "$SRC/klab-buildroot-cache.sh" status >/dev/null || true
for p in builds logs kernels toolchains exports jobs sessions initramfs buildroot buildenvs distro-toolchains userspaces; do
  [[ ! -e "$LAB/$p" && ! -L "$LAB/$p" ]] || { echo "legacy path created: $LAB/$p" >&2; exit 1; }
done
[[ -d "$LAB/work/buildroot" ]]
[[ -d "$LAB/work/buildroot-cache" ]]

echo 'PASS residual-path-audit'
