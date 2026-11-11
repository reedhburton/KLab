#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
grep -Fq 'buildroot_sdk_dir "$ARCH" "$brprofile"' "$ROOT/kernel-lab.sh"
grep -Fq 'buildroot_sdk_archive_path "$ARCH" "$brprofile"' "$ROOT/kernel-lab.sh"
grep -Fq '[[ -f "$archive" && -d "$sdk" && -x "$sdk/relocate-sdk.sh" ]]' "$ROOT/kernel-lab.sh"
# The offline branch may select only a fully materialized SDK/archive pair.
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
sdk="$T/sdk"; archive="$T/sdk.tar.gz"; mkdir "$sdk"; : >"$archive"; : >"$sdk/relocate-sdk.sh"; chmod +x "$sdk/relocate-sdk.sh"
[[ -f "$archive" && -d "$sdk" && -x "$sdk/relocate-sdk.sh" ]]
rm "$archive"; ! [[ -f "$archive" && -d "$sdk" && -x "$sdk/relocate-sdk.sh" ]]
echo 'offline-global-buildroot-sdk: PASS'
