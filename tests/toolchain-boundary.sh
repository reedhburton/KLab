#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
TC="$T/tc"; mkdir -p "$TC/bin"
cat >"$TC/bin/test-gcc" <<'EOF'
#!/bin/sh
case "$1" in
  -dumpfullversion) echo 12.3.0; exit 0 ;;
  -dumpversion) echo 12.3.0; exit 0 ;;
  -dumpmachine) echo x86_64-linux-gnu; exit 0 ;;
  -print-prog-name=*) n=${1#*=}; echo "${0%/*}/$n"; exit 0 ;;
esac
out=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then out=$2; shift 2; else shift; fi
done
[ -n "$out" ] || exit 3
: >"$out"
EOF
chmod +x "$TC/bin/test-gcc"
for x in cc1 as ld ar nm objcopy objdump strip readelf addr2line size strings ranlib; do printf '#!/bin/sh\nexit 0\n' >"$TC/bin/$x"; chmod +x "$TC/bin/$x"; done
j="$($ROOT/klab-toolchain-boundary.sh seal --root "$TC" --cc bin/test-gcc --json)"
dig="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["tree_sha256"])' "$j")"
$ROOT/klab-toolchain-boundary.sh verify --root "$TC" --cc bin/test-gcc --tree-sha256 "$dig" --family gcc --version 12.3.0 --target x86_64-linux-gnu >/dev/null
printf '#tamper\n' >>"$TC/bin/ar"
if $ROOT/klab-toolchain-boundary.sh verify --root "$TC" --cc bin/test-gcc --tree-sha256 "$dig" >/dev/null 2>&1; then echo 'FAIL: toolchain content tamper accepted' >&2; exit 1; fi
sed -i '$d' "$TC/bin/ar"
# Reseal restored content and prove an escaping helper is rejected.
$ROOT/klab-toolchain-boundary.sh seal --root "$TC" --cc bin/test-gcc >/dev/null
rm -f "$TC/bin/ld"; ln -s /bin/true "$TC/bin/ld"
if $ROOT/klab-toolchain-boundary.sh verify --root "$TC" --cc bin/test-gcc >/dev/null 2>&1; then echo 'FAIL: escaping toolchain symlink accepted' >&2; exit 1; fi
rm -f "$TC/bin/ld"; printf '#!/bin/sh\nexit 0\n' >"$TC/bin/ld"; chmod +x "$TC/bin/ld"
# Even an absolute link naming a file that exists inside the toolchain must be
# rejected: the toolchain is relocated to /tmp/klab-toolchain in the sandbox,
# so /bin/ar would resolve against the buildenv root instead.
ln -s /bin/ar "$TC/absolute-inroot-link"
if $ROOT/klab-toolchain-boundary.sh seal --root "$TC" --cc bin/test-gcc >/dev/null 2>&1; then echo 'FAIL: relocatability-breaking absolute symlink accepted' >&2; exit 1; fi
rm -f "$TC/absolute-inroot-link"
$ROOT/klab-toolchain-boundary.sh seal --root "$TC" --cc bin/test-gcc >/dev/null
if $ROOT/klab-toolchain-boundary.sh verify --root "$TC" --cc bin/test-gcc --version 99.0 >/dev/null 2>&1; then echo 'FAIL: compiler version mismatch accepted' >&2; exit 1; fi
if $ROOT/klab-toolchain-boundary.sh verify --root "$TC" --cc bin/test-gcc --target aarch64-linux-gnu >/dev/null 2>&1; then echo 'FAIL: compiler target mismatch accepted' >&2; exit 1; fi
rm -f "$TC/bin/strip"
if $ROOT/klab-toolchain-boundary.sh verify --root "$TC" --cc bin/test-gcc >/dev/null 2>&1; then echo 'FAIL: missing helper fell back to host' >&2; exit 1; fi
echo 'toolchain-boundary: PASS'
