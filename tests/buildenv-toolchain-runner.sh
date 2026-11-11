#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/be-root/usr/src/linux-test/scripts" "$T/module" "$T/fakebin" "$T/tc/bin"
printf 'all:\n\t@:\n' >"$T/be-root/usr/src/linux-test/Makefile"
printf '# synthetic\n' >"$T/be-root/usr/src/linux-test/scripts/Makefile.build"
printf 'pkg 1 x86_64 abc\n' >"$T/packages.txt"
printf 'pkg\t1\tx86_64\n' >"$T/installed.tsv"
cat >"$T/tc/bin/test-gcc" <<'EOF_GCC'
#!/bin/sh
case "$1" in
  -dumpfullversion) echo 12.3.0; exit 0 ;;
  -dumpversion) echo 12.3.0; exit 0 ;;
  -dumpmachine) echo x86_64-linux-gnu; exit 0 ;;
  -print-prog-name=*) n=${1#*=}; echo "${0%/*}/$n"; exit 0 ;;
esac
exit 0
EOF_GCC
chmod +x "$T/tc/bin/test-gcc"
for x in cc1 as ld ar nm objcopy objdump strip readelf addr2line size strings ranlib; do
  printf '#!/bin/sh\nexit 0\n' >"$T/tc/bin/$x"
  chmod +x "$T/tc/bin/$x"
done
tc_json="$("$ROOT/klab-toolchain-boundary.sh" seal --root "$T/tc" --cc bin/test-gcc --json)"
IFS=$'\t' read -r tc_sha tc_family tc_ver tc_target < <(python3 - "$tc_json" <<'PYJSON'
import json,sys
m=json.loads(sys.argv[1])
print('\t'.join(str(m[k]) for k in ('tree_sha256','family','version','target')))
PYJSON
)
out="$T/be.klabbuildenv"
"$ROOT/klab-buildenv.sh" create --root "$T/be-root" --provider test --release 1 --kernel-release test-kernel \
  --target-arch x86_64 --exec-arch x86_64 --provider-image sha256:2222222222222222222222222222222222222222222222222222222222222222 --recipe-version test \
  --build-dir usr/src/linux-test --package-manifest "$T/packages.txt" --installed-inventory "$T/installed.tsv" \
  --toolchain-tree-sha256 "$tc_sha" --toolchain-family "$tc_family" --toolchain-version "$tc_ver" \
  --toolchain-target "$tc_target" --toolchain-cc-relpath bin/test-gcc -o "$out" >/dev/null
id="$("$ROOT/klab-buildenv.sh" verify "$out")"
KLAB_HOME="$T/home" "$ROOT/klab-buildenv.sh" import "$out" >/dev/null
for x in as ld ar nm objcopy objdump strip; do
  cat >"$T/fakebin/$x" <<EOF_HOST
#!/bin/sh
echo HOST-$x >>'$T/host-tools-used'
exit 99
EOF_HOST
  chmod +x "$T/fakebin/$x"
done
cat >"$T/fakebin/bwrap" <<EOF_BWRAP
#!/bin/sh
printf '%s\\n' "\$@" >'$T/bwrap-args'
exit 0
EOF_BWRAP
chmod +x "$T/fakebin/bwrap"
PATH="$T/fakebin:$PATH" KLAB_HOME="$T/home" "$ROOT/klab-buildenv.sh" run-module "$id" \
  --toolchain-root "$T/tc" --toolchain-cc bin/test-gcc --toolchain-tree-sha256 "$tc_sha" \
  --toolchain-family gcc --toolchain-version 12.3.0 --toolchain-target x86_64-linux-gnu \
  --module "$T/module" --jobs 2 --kernel-arch x86 \
  --expect-provider test --expect-release 1 --expect-kernel-release test-kernel --expect-target-arch x86_64 >/dev/null
[[ ! -e "$T/host-tools-used" ]] || { echo 'FAIL: host target tool executed' >&2; exit 1; }
for want in \
  'CC=/tmp/klab-toolchain/bin/test-gcc' \
  'AS=/tmp/klab-toolchain/bin/as' \
  'LD=/tmp/klab-toolchain/bin/ld' \
  'AR=/tmp/klab-toolchain/bin/ar' \
  'NM=/tmp/klab-toolchain/bin/nm' \
  'OBJCOPY=/tmp/klab-toolchain/bin/objcopy' \
  'OBJDUMP=/tmp/klab-toolchain/bin/objdump' \
  'STRIP=/tmp/klab-toolchain/bin/strip' \
  'READELF=/tmp/klab-toolchain/bin/readelf' \
  'ADDR2LINE=/tmp/klab-toolchain/bin/addr2line' \
  'SIZE=/tmp/klab-toolchain/bin/size' \
  'STRINGS=/tmp/klab-toolchain/bin/strings' \
  'RANLIB=/tmp/klab-toolchain/bin/ranlib'; do
  grep -Fxq "$want" "$T/bwrap-args" || { echo "FAIL: missing explicit target tool $want" >&2; cat "$T/bwrap-args" >&2; exit 1; }
done
grep -Eq '^PATH=/tmp/klab-toolchain/[^:]+(:/tmp/klab-toolchain/[^:]+)*:/usr/bin:/bin:/usr/sbin:/sbin$' "$T/bwrap-args" || {
  echo 'FAIL: sandbox PATH does not use sealed toolchain + captured buildenv only' >&2; cat "$T/bwrap-args" >&2; exit 1; }
! grep -Fq "$T/fakebin" "$T/bwrap-args" || { echo 'FAIL: caller PATH leaked into sandbox' >&2; exit 1; }
# A valid buildenv for the same toolchain but a different kernel must be rejected.
if PATH="$T/fakebin:$PATH" KLAB_HOME="$T/home" "$ROOT/klab-buildenv.sh" run-module "$id" \
  --toolchain-root "$T/tc" --toolchain-cc bin/test-gcc --toolchain-tree-sha256 "$tc_sha" \
  --toolchain-family gcc --toolchain-version 12.3.0 --toolchain-target x86_64-linux-gnu --module "$T/module" \
  --kernel-arch x86 --expect-provider test --expect-release 1 --expect-kernel-release wrong-kernel --expect-target-arch x86_64 >/dev/null 2>&1; then
  echo 'FAIL: buildenv accepted wrong target kernel identity' >&2; exit 1
fi
# Caller cannot override Linux ARCH inconsistently with the target architecture.
if PATH="$T/fakebin:$PATH" KLAB_HOME="$T/home" "$ROOT/klab-buildenv.sh" run-module "$id" \
  --toolchain-root "$T/tc" --toolchain-cc bin/test-gcc --toolchain-tree-sha256 "$tc_sha" \
  --toolchain-family gcc --toolchain-version 12.3.0 --toolchain-target x86_64-linux-gnu --module "$T/module" \
  --kernel-arch arm64 --expect-provider test --expect-release 1 --expect-kernel-release test-kernel --expect-target-arch x86_64 >/dev/null 2>&1; then
  echo 'FAIL: buildenv accepted inconsistent kernel ARCH' >&2; exit 1
fi
printf '#mutation\n' >>"$T/tc/bin/ar"
"$ROOT/klab-toolchain-boundary.sh" seal --root "$T/tc" --cc bin/test-gcc >/dev/null
new_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tree_sha256"])' "$T/tc/.klab-toolchain-boundary.json")"
if PATH="$T/fakebin:$PATH" KLAB_HOME="$T/home" "$ROOT/klab-buildenv.sh" run-module "$id" \
  --toolchain-root "$T/tc" --toolchain-cc bin/test-gcc --toolchain-tree-sha256 "$new_sha" \
  --toolchain-family gcc --toolchain-version 12.3.0 --toolchain-target x86_64-linux-gnu --module "$T/module" \
  --expect-provider test --expect-release 1 --expect-kernel-release test-kernel --expect-target-arch x86_64 >/dev/null 2>&1; then
  echo 'FAIL: buildenv accepted a different resealed toolchain tree' >&2
  exit 1
fi
echo 'buildenv-toolchain-runner: PASS'
