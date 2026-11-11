#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
stage="$T/final.klab-import.123"; final="$T/final"
mkdir -p "$stage/root/usr/src/linux-headers-k" "$stage/packages" "$T/home"
cat > "$T/manifest.json" <<'JSON'
{"provider":"ubuntu","release":"17.04","kernel_release":"k","arch":"x86_64","build_image":"ubuntu:17.04","created_at":"now","payloads":[{"build_dir_rel":"root/usr/src/linux-headers-k","source_dir_rel":"","modules_dir_rel":""}]}
JSON
bash -c '
set -euo pipefail
export KLAB_ROOT="$2/home"
source "$6/lib/klab-root.sh"
export KLAB_ARCH_MODEL_BIN="$6/lib/arch-model.sh"
source <(sed "/^main \"\\\$@\"$/d" "$1")
LAB_HOME="$2/home"
fixup_distro_env "$3" "$4" "$5"
source "$3/bundle.env"
[[ "$BUNDLE_DIR" == "$5" ]]
[[ "$BUNDLE_BUILD_DIR" == "$5/root/usr/src/linux-headers-k" ]]
! grep -q "klab-import" "$3/bundle.env"
! grep -q "if \\[\\[" "$3/bundle.env"
' _ "$ROOT/klab-bundle.sh" "$T" "$stage" "$T/manifest.json" "$final" "$ROOT"
# Upstream atomic imports must likewise serialize the installed path, not the staging path.
grep -q 'BUNDLE_DIR=$(quote_env "$installed_dest")' "$ROOT/klab-bundle.sh"
grep -q 'BUNDLE_BUILD_DIR=$(quote_env "$installed_dest/build")' "$ROOT/klab-bundle.sh"
grep -Fq 'local imported="$KERNELS/upstream/$version/$arch/$profile/build"' "$ROOT/klab-bundle.sh"
grep -Fq '"$installed_dest/source" > "$dest/build/.klab-source-dir"' "$ROOT/klab-bundle.sh"
echo 'import-env-relocation: PASS'
