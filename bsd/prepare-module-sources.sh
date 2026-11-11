#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 2 ]] || { echo "usage: prepare-module-sources.sh TARGET REPO" >&2; exit 2; }
target="$1"; repo="$2"; out="$repo/bsd/sources"; mkdir -p "$out"
fetch(){ local url="$1" file="$2"; [[ -s "$file" ]] || curl -fL --retry 3 -C - -o "$file" "$url"; }
iso_builder(){
 local tree="$1" iso="$2"
 if command -v genisoimage >/dev/null 2>&1; then genisoimage -quiet -R -J -o "$iso" "$tree"
 elif command -v mkisofs >/dev/null 2>&1; then mkisofs -quiet -R -J -o "$iso" "$tree"
 elif command -v docker >/dev/null 2>&1; then
  docker run --rm -v "$tree:/src:ro" -v "$out:/out" debian:trixie-slim sh -c "apt-get update >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends genisoimage >/dev/null && genisoimage -quiet -R -J -o /out/$(basename "$iso") /src"
 else echo "klab: genisoimage, mkisofs, or Docker is required to prepare BSD module sources" >&2; return 2; fi
 sha256sum "$iso" >"$iso.sha256"
}
case "$target" in
 netbsd:11.0:*)
  archive="$out/netbsd-11.0-syssrc.tgz"; iso="$out/netbsd-11.0-syssrc.iso"
  fetch https://cdn.netbsd.org/pub/NetBSD/NetBSD-11.0/source/sets/syssrc.tgz "$archive"
  printf '%s  %s\n' 318d451ecc83749607d5448198c02663ea5f0b7f4cc74fb565747f86eead7b66b5809a37deee219dc6ddb2e5ee332d1cbb94c1a4e9db63620c3abd7586fb3057 "$archive" | sha512sum -c -
  if [[ ! -s "$iso" || ! -s "$iso.sha256" ]] || ! (cd "$out" && sha256sum -c "$(basename "$iso.sha256")"); then
   tmp="$(mktemp -d /tmp/klab-netbsd-source.XXXXXX)"; trap 'rm -rf "$tmp"' EXIT
   tar -xzf "$archive" -C "$tmp" usr/src/sys usr/src/common; iso_builder "$tmp" "$iso"
  fi;;
 dragonfly:6.2.2:x86_64|dragonfly:6.4.2:x86_64)
  version="${target#*:}"; version="${version%%:*}"; archive="$out/dragonfly-v${version}.tar.gz"; iso="$out/dragonfly-v${version}-src.iso"
  case "$version" in 6.2.2) digest=88e07813caf95cb99f5273e2c12542a972a9e10c2fe2dbea8351695508986d25;; 6.4.2) digest=26c450b87a38f2611191896051340b77245bf356d29b1cd67a02d423cc178d41;; esac
  fetch "https://codeload.github.com/DragonFlyBSD/DragonFlyBSD/tar.gz/refs/tags/v${version}" "$archive"
  printf '%s  %s\n' "$digest" "$archive" | sha256sum -c -
  if [[ ! -s "$iso" || ! -s "$iso.sha256" ]] || ! (cd "$out" && sha256sum -c "$(basename "$iso.sha256")"); then
   tmp="$(mktemp -d /tmp/klab-dragonfly-source.XXXXXX)"; trap 'rm -rf "$tmp"' EXIT
   tar -xzf "$archive" -C "$tmp"; iso_builder "$tmp" "$iso"
  fi;;
 *) echo "klab: module source preparation is unsupported for $target" >&2; exit 2;;
esac
printf 'BSD module source ready: %s\n' "$iso"
