#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
usage(){ cat <<'USAGE'
Usage: install-m2.sh [--check-only] KLAB_SOURCE_DIR

Preflights the complete M2 patch set against temporary copies first. The target
source tree is not modified unless every patch applies and syntax validation
passes. On install, original core scripts and replaced helper files are saved
under .klab-m2-backup-<timestamp>/.

The v16/v17 typed .klabtoolchain format is intentionally not rewritten. The
verified .klabbuildenv manifest pins the expected toolchain tree digest, and the
runtime boundary verifier checks the imported toolchain against that digest.
USAGE
}
die(){ printf 'install-m2: ERROR: %s\n' "$*" >&2; exit 1; }
check_only=0
if [[ "${1:-}" == --check-only ]]; then check_only=1; shift; fi
[[ $# == 1 ]] || { usage; exit 2; }
target="$(cd -- "$1" 2>/dev/null && pwd)" || die "source directory not found: $1"
[[ -f "$target/kernel-lab.sh" ]] || die "kernel-lab.sh missing in $target"
[[ -f "$target/klab-bundle.sh" ]] || die "klab-bundle.sh missing in $target"
command -v python3 >/dev/null || die 'python3 is required'

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp -a "$target/kernel-lab.sh" "$tmp/kernel-lab.sh"
cp -a "$target/klab-bundle.sh" "$tmp/klab-bundle.sh"

python3 "$SELF_DIR/apply-provider-refactor.py" "$tmp/kernel-lab.sh" >/dev/null
python3 "$SELF_DIR/apply-buildenv-refactor.py" "$tmp/kernel-lab.sh" >/dev/null
python3 "$SELF_DIR/apply-buildenv-transfer.py" "$tmp/klab-bundle.sh" >/dev/null
python3 "$SELF_DIR/apply-buildenv-import.py" "$tmp/kernel-lab.sh" >/dev/null
python3 "$SELF_DIR/apply-atomic-target-import.py" "$tmp/klab-bundle.sh" >/dev/null
# Apply the toolchain boundary last: it hardens both the final bundle helper
# and runner shapes produced by the provider/buildenv patches above.
python3 "$SELF_DIR/apply-toolchain-boundary.py" "$tmp/klab-bundle.sh" "$tmp/kernel-lab.sh" >/dev/null

# Root integration must be preflighted on the same temporary core files.
for rel in klab-buildenv.sh klab-distro-toolchain.sh klab-artifact.sh; do
  cp -a "$SELF_DIR/$rel" "$tmp/$rel"
done
mkdir -p "$tmp/lib"
cp -a "$SELF_DIR/lib/klab_buildenv.py" "$SELF_DIR/lib/klab_distro_toolchain.py" "$tmp/lib/"
[[ ! -f "$SELF_DIR/lib/arch-model.sh" ]] || cp -a "$SELF_DIR/lib/arch-model.sh" "$tmp/lib/"
"$SELF_DIR/apply-root-layout.sh" "$tmp" >/dev/null

bash -n "$tmp/kernel-lab.sh"
bash -n "$tmp/klab-bundle.sh"
for marker in KLAB_PROVIDER_REFACTOR_M2 KLAB_BUILDENV_M2 KLAB_BUILDENV_IMPORT_M2 KLAB_TOOLCHAIN_RUNTIME_BOUNDARY_M2; do
  grep -q "$marker" "$tmp/kernel-lab.sh" || die "preflight missing runner marker $marker"
done
for marker in KLAB_BUILDENV_TRANSFER_M2 KLAB_ATOMIC_TARGET_IMPORT_M2 KLAB_TOOLCHAIN_BOUNDARY_M2; do
  grep -q "$marker" "$tmp/klab-bundle.sh" || die "preflight missing bundle marker $marker"
done
printf 'M2 preflight: PASS for %s\n' "$target"
(( check_only == 0 )) || exit 0

stamp="$(date +%Y%m%d-%H%M%S)"
backup="$target/.klab-m2-backup-$stamp"
mkdir -p "$backup/core" "$backup/runtime"
cp -a "$target/kernel-lab.sh" "$target/klab-bundle.sh" "$backup/core/"

# Back up only paths M2 owns/replaces. Existing unrelated lib/provider files are
# untouched. An ABSENT marker lets an operator distinguish newly added files.
owned=(
  klab-buildenv.sh klab-toolchain-boundary.sh klab-distro-toolchain.sh klab-artifact.sh
  klab klab-root lib/klab-root.sh lib/klab_paths.py lib/klab_distro_toolchain.py lib/arch-model.sh
  lib/provider-core.sh lib/buildenv-capture.sh lib/klab_buildenv.py lib/toolchain_boundary.py
  lib/backends/apt.sh lib/backends/rpm.sh
  providers/ubuntu.sh providers/debian.sh providers/centos.sh providers/fedora.sh providers/rhel.sh
  providers/_template.sh.example providers/PROVIDER-API.md
  providers/experimental/rocky.sh providers/experimental/almalinux.sh
)
for rel in "${owned[@]}"; do
  if [[ -e "$target/$rel" ]]; then
    mkdir -p "$backup/runtime/$(dirname "$rel")"
    cp -a "$target/$rel" "$backup/runtime/$rel"
  else
    mkdir -p "$backup/runtime/$(dirname "$rel")"
    : >"$backup/runtime/$rel.ABSENT"
  fi
done

# Core scripts were fully preflighted before this point.
cp -a "$tmp/kernel-lab.sh" "$target/kernel-lab.sh.m2-new"
cp -a "$tmp/klab-bundle.sh" "$target/klab-bundle.sh.m2-new"
mv -f "$target/kernel-lab.sh.m2-new" "$target/kernel-lab.sh"
mv -f "$target/klab-bundle.sh.m2-new" "$target/klab-bundle.sh"

mkdir -p "$target/lib/backends" "$target/providers"
for rel in "${owned[@]}"; do
  mkdir -p "$target/$(dirname "$rel")"
  cp -a "$SELF_DIR/$rel" "$target/$rel"
done
chmod +x "$target/kernel-lab.sh" "$target/klab-bundle.sh" "$target/klab-buildenv.sh" "$target/klab-toolchain-boundary.sh"

# Validate the installed bytes, not only the temporary copies.
bash -n "$target/kernel-lab.sh"
bash -n "$target/klab-bundle.sh"
find "$target/providers" "$target/lib" -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
python3 -m py_compile "$target/lib/klab_buildenv.py" "$target/lib/toolchain_boundary.py"
printf 'M2 install: PASS\nBackup: %s\n' "$backup"
