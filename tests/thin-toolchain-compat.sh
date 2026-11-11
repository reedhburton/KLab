#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/self" "$T/home" "$T/tc/bin" "$T/job/module"
printf '#!/bin/sh\nexit 0\n' >"$T/tc/bin/gcc"; chmod +x "$T/tc/bin/gcc"
cat >"$T/self/klab-buildenv.sh" <<'EOF_HELPER'
#!/bin/sh
set -eu
cmd=$1; shift
case "$cmd" in
  assert-installed)
    printf '%s\n' '{"toolchain_tree_sha256":"deadbeef"}'
    ;;
  run-module)
    printf '%s\n' "$@" >"$KLAB_TEST_LOG"
    mod=''
    while [ "$#" -gt 0 ]; do
      case "$1" in --module) mod=$2; shift 2;; *) shift;; esac
    done
    : >"$mod/fake.ko"
    ;;
  *) exit 93;;
esac
EOF_HELPER
chmod +x "$T/self/klab-buildenv.sh"
cat >"$T/kernel-lab.sh" <<'EOF_KLAB'
#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR="${KLAB_TEST_SELF_DIR}"
LAB_HOME="${KLAB_TEST_HOME}"
BUNDLE_BIN="$SELF_DIR/klab-bundle.sh"
ARCH=x86_64
JOBS=1
OFFLINE=1
say(){ :; }
die(){ echo "DIE:$*" >&2; exit 1; }
linux_karch(){ echo x86; }
bundle_tool(){ :; }
cmd_fetch(){ :; }
parse_target(){ :; }
bundle_existing_dir_for(){ echo /tmp/noop; }
klab_provider_capture_buildenv(){ :; }
bundle_load(){
  BUNDLE_BUILDENV_ID=be-id
  BUNDLE_TOOLCHAIN_BOUND=1
  BUNDLE_TOOLCHAIN_DIR="$KLAB_TEST_TC"
  BUNDLE_TOOLCHAIN_CC_REL=bin/gcc
  BUNDLE_TOOLCHAIN_CC="$KLAB_TEST_TC/bin/gcc"
  BUNDLE_TOOLCHAIN_FAMILY=gcc
  BUNDLE_TOOLCHAIN_VERSION=12.3.0
  BUNDLE_TOOLCHAIN_TARGET=x86_64-linux-gnu
  BUNDLE_TOOLCHAIN_CROSS_PREFIX_REL=''
  BUNDLE_PROVIDER=test
  BUNDLE_DISTRO_RELEASE=1
  BUNDLE_KERNEL_RELEASE=test-kernel
  BUNDLE_ARCH=x86_64
  # Deliberately NO BUNDLE_TOOLCHAIN_TREE_SHA256 and no boundary marker.
}
cmd_prepare() {
 local target="$1" provider="${1%%:*}" profile=normal output=/tmp/out.klab artifact_dir=/tmp/artifacts tc_mode=none
 if [[ "$provider" == upstream ]]; then :; else
   say "Fetching exact distro kernel artifacts for $target"
   cmd_fetch "$target" >/dev/null
 fi
 local args=(create "$target" --profile "$profile" -o "$output")
 bundle_tool "${args[@]}"
}
build_external_module_bundle() {
 local target="$1" module_dir="$2" job="$KLAB_TEST_JOB" provider image
 bundle_load "$target"
 say "Building module for $target in isolated job $(basename "$job")"
 if [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 || "$OFFLINE" == 1 ]]; then :; fi
}
main(){ :; }
if [[ "${1:-}" == selftest ]]; then build_external_module_bundle test:1:test-kernel "$KLAB_TEST_JOB/module"; fi
EOF_KLAB
python3 "$ROOT/apply-buildenv-refactor.py" "$T/kernel-lab.sh" >/dev/null
bash -n "$T/kernel-lab.sh"
KLAB_TEST_SELF_DIR="$T/self" KLAB_TEST_HOME="$T/home" KLAB_TEST_TC="$T/tc" KLAB_TEST_JOB="$T/job" KLAB_TEST_LOG="$T/run.args" \
  bash "$T/kernel-lab.sh" selftest
[[ -f "$T/job/module/fake.ko" ]] || { echo 'FAIL: patched runner did not invoke buildenv helper' >&2; exit 1; }
grep -Fxq -- '--toolchain-tree-sha256' "$T/run.args" || { echo 'FAIL: missing digest option' >&2; cat "$T/run.args" >&2; exit 1; }
# Verify the value following the option is the digest recovered from buildenv.
python3 - "$T/run.args" <<'PY'
import sys
x=open(sys.argv[1]).read().splitlines()
i=x.index('--toolchain-tree-sha256')
assert x[i+1]=='deadbeef', x
PY
echo 'thin-toolchain-compat: PASS'
