#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat >"$T/kernel-lab.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR=/tmp
LAB_HOME=/tmp/lab
BUNDLE_BIN="$SELF_DIR/klab-bundle.sh"
ARCH=x86_64
JOBS=4
OFFLINE=0
cmd_prepare() {
 local target="$1" provider="${1%%:*}" profile=normal output=/tmp/out.klab artifact_dir=/tmp/artifacts
 if [[ "$provider" == upstream ]]; then :; else
   say "Fetching exact distro kernel artifacts for $target"
   cmd_fetch "$target" >/dev/null
 fi
 local args=(create "$target" --profile "$profile" -o "$output")
 bundle_tool "${args[@]}"
}
cmd_import_bundle() {
 (($# >= 1)) || die "usage"
 bundle_tool import "$@"
}
build_external_module_bundle() {
 local target="$1" module_dir="$2" job=/tmp/job provider image
 bundle_load "$target"
 say "Building module for $target in isolated job $(basename "$job")"
 if [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 || "$OFFLINE" == 1 ]]; then :; fi
}

main() {
 local cmd="${1:-}"
 case "$cmd" in
   toolchain) shift; cmd_toolchain "$@" ;;
   *) : ;;
 esac
}
EOF
python3 "$ROOT/apply-buildenv-refactor.py" "$T/kernel-lab.sh" >/dev/null
python3 "$ROOT/apply-buildenv-import.py" "$T/kernel-lab.sh" >/dev/null
bash -n "$T/kernel-lab.sh"
grep -q 'KLAB_BUILDENV_M2' "$T/kernel-lab.sh"
grep -q 'klab_provider_capture_buildenv' "$T/kernel-lab.sh"
grep -q 'run-module "$BUNDLE_BUILDENV_ID"' "$T/kernel-lab.sh"
grep -q 'BUNDLE_TOOLCHAIN_TREE_SHA256' "$T/kernel-lab.sh"
grep -q 'assert-installed "$BUNDLE_BUILDENV_ID"' "$T/kernel-lab.sh"
grep -q 'KLAB_BUILDENV_IMPORT_M2' "$T/kernel-lab.sh"
grep -Fq 'buildenv) shift; "$BUILDENV_BIN" "$@" ;;' "$T/kernel-lab.sh"
echo 'buildenv-patcher-smoke: PASS'
