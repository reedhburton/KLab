#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
k="$ROOT/kernel-lab.sh"
grep -Fq 'toolchain_runtime_library_path()' "$k"
for lib in libbfd libopcodes libmpfr libmpc libgmp libgcc_s 'libstdc++'; do
  grep -Fq -- "-name '$lib" "$k"
done
# A captured libc/loader must never be injected into host make processes.
! sed -n '/toolchain_runtime_library_path()/,/^}/p' "$k" | grep -Eq -- "-name 'libc|ld-linux"
grep -Fq 'KLAB_TC_MAKE_ARGS+=("CC=$cc" "HOSTCC=$(command -v gcc)" "HOSTCFLAGS=-fno-pie -no-pie -fcf-protection=none -fgnu89-inline" "HOSTLDFLAGS=-no-pie")' "$k"
echo 'legacy sealed toolchain runtime and host compiler separation: PASS'

grep -Fq 'Native archived compilers are absolute paths' "$k"
grep -Fq '&& -n "${BUNDLE_TOOLCHAIN_CROSS_PREFIX:-}"' "$k"
grep -Fq 'if [[ ! -x "${bound_cross_prefix}ld" && -x "$BUNDLE_TOOLCHAIN_DIR/bin/ld" ]]' "$k"
grep -Fq 'bound_cross_prefix="$BUNDLE_TOOLCHAIN_DIR/bin/"' "$k"
grep -Fq 'KLAB_TC_MAKE_ARGS+=("CROSS_COMPILE=$bound_cross_prefix")' "$k"
