#!/usr/bin/env bash
set -Eeuo pipefail

SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
[[ $# -eq 4 ]] || {
  echo "usage: $0 INPUT.klab TARGET ARCH EVIDENCE_DIR" >&2
  exit 2
}

artifact="$(realpath "$1")"
target="$2"
arch="$3"
evidence="$(realpath -m "$4")"
[[ -f "$artifact" ]] || { echo "fresh-root gate: artifact not found: $artifact" >&2; exit 2; }
[[ ! -e "$evidence" ]] || { echo "fresh-root gate: evidence already exists: $evidence" >&2; exit 2; }

mkdir -p "$evidence"
work="$evidence/.work"
root="$work/root"
repo="$work/repo"
repacked="$work/repacked.klab"
mkdir -p "$work/home" "$repo"

cleanup() {
  # Imported source archives intentionally preserve read-only modes. Restore
  # owner write/search permission before removing this gate's private root.
  [[ ! -e "$work" ]] || chmod -R u+rwX -- "$work" 2>/dev/null || true
  rm -rf -- "$work"
}
trap cleanup EXIT

export HOME="$work/home"
export KLAB_ROOT="$root"
export KLAB_HOME="$root"
export KLAB_REPO="$repo"
export KLAB_COMPAT_LINKS=0
export KLAB_OFFLINE=1
export KLAB_ARCH="$arch"
case "$arch" in
  mips|mipsel|mips64|mips64el)
    export KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 KLAB_ENABLE_EXPERIMENTAL_E2E=1
    ;;
esac

status="$evidence/status.tsv"
printf 'phase\tstatus\n' > "$status"
phase() { printf '%s\t%s\n' "$1" "$2" >> "$status"; }

sha256sum "$artifact" > "$evidence/input.sha256"
"$SELF/klab-bundle.sh" inspect "$artifact" > "$evidence/input.inspect.txt"

"$SELF/klab" setup --root "$root" --repo "$repo" > "$evidence/setup.log" 2>&1
phase setup PASS

"$SELF/klab" load "$artifact" > "$evidence/load.log" 2>&1
phase load PASS

"$SELF/klab" advanced info "$target" > "$evidence/imported-info.txt" 2>&1
grep -Eq "^Architecture:[[:space:]]+$arch$" "$evidence/imported-info.txt"
phase imported-info PASS

"$SELF/beta-tools/offline-repack-klab.sh" "$target" "$repacked" "$root" "$arch" > "$evidence/repack.log" 2>&1
phase repack PASS

"$SELF/klab-bundle.sh" verify "$repacked" > "$evidence/verify-repacked.log" 2>&1
"$SELF/klab-bundle.sh" inspect "$repacked" > "$evidence/repacked.inspect.txt"
sha256sum "$repacked" > "$evidence/repacked.sha256"
mkdir -p "$evidence/repacked-metadata"
tar -xf "$repacked" -C "$evidence/repacked-metadata" FORMAT_VERSION manifest.json SHA256SUMS
phase verify-repacked PASS

printf 'PASS\n' > "$evidence/RESULT"
cat > "$evidence/summary.txt" <<EOF
KLab fresh-root offline gate: PASS
target=$target
arch=$arch
offline=$KLAB_OFFLINE
fresh_root=yes
import=PASS
repack=PASS
verify_repacked=PASS
temporary_expanded_root=removed
EOF

printf 'PASS: fresh-root offline import and repack for %s/%s\n' "$target" "$arch"
