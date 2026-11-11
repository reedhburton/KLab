#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# Execute the production selector without sourcing klab-bundle.sh (which is a CLI).
eval "$(awk '/^toolchain_import_dest\(\)/,/^}/' "$ROOT/klab-bundle.sh")"
store="$T/toolchains"; mkdir -p "$store"
id=kernelorg-gcc-11.4.0-x86_64-to-x86_64-linux
a=$(printf a%.0s {1..64}); b=$(printf b%.0s {1..64})
[[ "$(toolchain_import_dest "$store" "$id" "$a")" == "$store/$id" ]]
mkdir -p "$store/$id"; printf '%s\n' "$a" >"$store/$id/.klab-toolchain.sha256"
[[ "$(toolchain_import_dest "$store" "$id" "$a")" == "$store/$id" ]]
[[ "$(toolchain_import_dest "$store" "$id" "$b")" == "$store/$id--$b" ]]
mkdir -p "$store/$id--$b"; printf '%s\n' "$b" >"$store/$id--$b/.klab-toolchain.sha256"
[[ "$(toolchain_import_dest "$store" "$id" "$b")" == "$store/$id--$b" ]]
grep -Fq 'tc_dest="$(toolchain_import_dest "$TOOLCHAINS" "$tc_id" "$tc_sha")"' "$ROOT/klab-bundle.sh"
echo 'toolchain-import-content-addressing: PASS'
