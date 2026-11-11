#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
version="$(tr -d '\r\n' < "$SELF/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]] || { echo "invalid VERSION: $version" >&2; exit 2; }
outdir="${1:-$SELF/../release-out}"; name="klab-$version"; stage="$(mktemp -d)"; verify=""
cleanup() { rm -rf -- "$stage"; [[ -z "$verify" ]] || rm -rf -- "$verify"; }
trap cleanup EXIT
mkdir -p "$outdir" "$stage/$name"
tar -C "$SELF" --exclude='./.git' --exclude='./__pycache__' --exclude='*/__pycache__' --exclude='*.pyc' --exclude='./release-out' -cf - . | tar -C "$stage/$name" -xf -
find "$stage/$name" -type f ! -name MANIFEST.sha256 -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sed "s#$stage/$name/##" > "$stage/$name/MANIFEST.sha256"
archive="$outdir/$name.tar.gz"; epoch="${SOURCE_DATE_EPOCH:-1791439200}"
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner -C "$stage" -czf "$archive" "$name"
sha256sum "$archive" > "$archive.sha256"
verify="$(mktemp -d)"; tar -xzf "$archive" -C "$verify"; (cd "$verify/$name" && sha256sum -c MANIFEST.sha256 >/dev/null)
printf '%s\n' "$archive"
