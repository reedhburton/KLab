#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
grep -Fq '"$root/usr/lib"' "$ROOT/kernel-lab.sh" || { echo 'native session staging does not make /lib writable' >&2; exit 1; }
tmp=$(mktemp -d); trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT
mkdir -p "$tmp/root/usr/lib" "$tmp/modules/source"; ln -s usr/lib "$tmp/root/lib"; printf module >"$tmp/modules/source/test.ko"; chmod 0555 "$tmp/root/usr/lib"
chmod u+w "$tmp/root/usr/lib"; mkdir -p "$tmp/root/lib/modules"; cp -a "$tmp/modules/source" "$tmp/root/lib/modules/1.0"
test -s "$tmp/root/lib/modules/1.0/test.ko"
echo 'native session module staging: PASS'
