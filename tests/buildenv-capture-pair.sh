#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/export-root/usr/src/linux-test/scripts" "$T/packages" "$T/tc/bin" "$T/fakebin"
printf 'all:\n\t@:\n' >"$T/export-root/usr/src/linux-test/Makefile"
printf '# synthetic\n' >"$T/export-root/usr/src/linux-test/scripts/Makefile.build"
printf 'debdata\n' >"$T/packages/linux-test.deb"
(cd "$T/packages" && sha256sum linux-test.deb >PACKAGES.sha256)
cat >"$T/tc/bin/test-gcc" <<'EOS'
#!/bin/sh
case "$1" in
  -dumpfullversion) echo 12.3.0; exit 0 ;;
  -dumpversion) echo 12.3.0; exit 0 ;;
  -dumpmachine) echo x86_64-linux-gnu; exit 0 ;;
  -print-prog-name=*) n=${1#*=}; echo "${0%/*}/$n"; exit 0 ;;
esac
exit 0
EOS
chmod +x "$T/tc/bin/test-gcc"
for x in cc1 as ld ar nm objcopy objdump strip readelf addr2line size strings ranlib; do
  printf '#!/bin/sh\nexit 0\n' >"$T/tc/bin/$x"; chmod +x "$T/tc/bin/$x"
done
tc_json="$($ROOT/klab-toolchain-boundary.sh seal --root "$T/tc" --cc bin/test-gcc --json)"
IFS=$'\t' read -r tc_sha tc_family tc_ver tc_target < <(python3 - "$tc_json" <<'PY'
import json,sys
m=json.loads(sys.argv[1]); print('\t'.join(str(m[k]) for k in ('tree_sha256','family','version','target')))
PY
)
cat >"$T/mock-runtime" <<'EOF_MOCK'
#!/usr/bin/env bash
set -eu
printf 'CALL:' >>"$MOCK_LOG"; printf ' <%s>' "$@" >>"$MOCK_LOG"; printf '\n' >>"$MOCK_LOG"
cmd=$1; shift
case "$cmd" in
  create|start|rm) exit 0 ;;
  image)
    [ "${1:-}" = inspect ] && { echo sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; exit 0; }
    ;;
  export)
    tar -C "$MOCK_ROOT" -cf - .
    exit 0
    ;;
  exec)
    # Find the container name after any docker/podman exec options.
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -e|--env) shift 2 ;;
        --env=*) shift ;;
        -*) shift ;;
        *) break ;;
      esac
    done
    [ "$#" -gt 0 ] || exit 2
    shift # container name
    if [ "${1:-}" = uname ] && [ "${2:-}" = -m ]; then echo x86_64; exit 0; fi
    case "$*" in *dpkg-query*) printf 'pkg\t1\tx86_64\n';; esac
    exit 0
    ;;
esac
exit 2
EOF_MOCK
chmod +x "$T/mock-runtime"
cat >"$T/fakebin/bwrap" <<'EOF_BWRAP'
#!/bin/sh
# Synthetic final artifact smoke: argument validation occurs before this point.
exit 0
EOF_BWRAP
chmod +x "$T/fakebin/bwrap"
export PATH="$T/fakebin:$PATH"
export MOCK_LOG="$T/runtime.log" MOCK_ROOT="$T/export-root"
export KLAB_CONTAINER_RUNTIME="$T/mock-runtime"
export KLAB_BUILDENV_BIN="$ROOT/klab-buildenv.sh"
export KLAB_BUILDENV_TOOLCHAIN_ROOT="$T/tc" KLAB_BUILDENV_TOOLCHAIN_JSON="$tc_json"
export KLAB_BUILDENV_TOOLCHAIN_TREE_SHA256="$tc_sha" KLAB_BUILDENV_TOOLCHAIN_FAMILY="$tc_family"
export KLAB_BUILDENV_TOOLCHAIN_VERSION="$tc_ver" KLAB_BUILDENV_TOOLCHAIN_TARGET="$tc_target" KLAB_BUILDENV_TOOLCHAIN_CC_REL=bin/test-gcc
SELF_DIR="$ROOT"
die(){ echo "TEST-DIE: $*" >&2; exit 1; }
# shellcheck disable=SC1091
source "$ROOT/lib/buildenv-capture.sh"
out="$T/out.klabbuildenv"
klab_buildenv_capture_container ubuntu 1 test-kernel x86_64 test:image ':' "$T/packages" ':' /usr/src/linux-test "$out"
[[ -f "$out" ]] || { echo 'FAIL: capture did not produce artifact' >&2; exit 1; }
"$ROOT/klab-buildenv.sh" verify "$out" --deep >/dev/null
grep -Fq "$T/tc:/klab-toolchain:ro" "$T/runtime.log" || { echo 'FAIL: exact toolchain was not mounted read-only into provider capture' >&2; cat "$T/runtime.log" >&2; exit 1; }
grep -Fq 'KLAB_TC_READELF=/klab-toolchain/bin/readelf' "$T/runtime.log" || { echo 'FAIL: pair validation did not bind target readelf' >&2; cat "$T/runtime.log" >&2; exit 1; }
grep -Fq 'KLAB_TC_ADDR2LINE=/klab-toolchain/bin/addr2line' "$T/runtime.log" || { echo 'FAIL: pair validation did not bind target addr2line' >&2; exit 1; }
grep -Fq 'KLAB_KERNEL_ARCH=x86' "$T/runtime.log" || { echo 'FAIL: target kernel ARCH not propagated to pair validation' >&2; exit 1; }
manifest="$T/manifest.json"
tar --zstd -xOf "$out" manifest.json >"$manifest"
[[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["toolchain_tree_sha256"])' "$manifest")" == "$tc_sha" ]] || { echo 'FAIL: buildenv did not independently pin toolchain tree' >&2; exit 1; }
echo 'buildenv-capture-pair: PASS'
