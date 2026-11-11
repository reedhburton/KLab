#!/usr/bin/env bash
set -u
target="${1:-}"; root="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab-data}}"
echo "target=$target"; echo "root=$root"
command -v gcc >/dev/null && { echo "host_gcc=$(gcc --version | head -1)"; } || echo "host_gcc=MISSING"
command -v qemu-system-x86_64 >/dev/null && echo "qemu_x86_64=$(command -v qemu-system-x86_64)" || echo "qemu_x86_64=MISSING"
echo "-- target files --"
find "$root/targets" -maxdepth 7 -type f \( -name bundle.env -o -name '*.klabbuildenv' -o -name '*.klabdistrotoolchain' \) 2>/dev/null | grep -E "$(printf '%s' "$target"|tr ':' '/').*|$(printf '%s' "$target"|cut -d: -f2- |tr ':' '.*')" | head -80 || true
echo "-- relevant package/toolchain evidence --"
find "$root" -type f \( -name 'compiler.json' -o -name 'packages.tsv' -o -name 'bundle.env' \) -print 2>/dev/null | while read -r f; do
  if grep -Eqi 'gcc|libelf|elfutils|compiler' "$f" 2>/dev/null; then echo "### $f"; grep -Ei 'gcc|libelf|elfutils|compiler' "$f" 2>/dev/null | head -60; fi
done | head -500
