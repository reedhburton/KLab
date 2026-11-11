#!/usr/bin/env bash
set -euo pipefail
RELEASES=(12.04 14.04 16.04 18.04 20.04 22.04 24.04)
ARCH=x86_64
KLAB_ROOT="${KLAB_ROOT:-${HOME}/klab}"
STORE="${KLAB_NATIVE_ROOTFS_STORE:-$KLAB_ROOT/artifacts/userspaces/ubuntu}"
RUNTIME="${KLAB_CONTAINER_RUNTIME:-docker}"
die(){ echo "klab-ubuntu-native-rootfs: ERROR: $*" >&2; exit 1; }
path_for(){ printf '%s/%s/%s/rootfs.tar.zst\n' "$STORE" "$1" "$ARCH"; }
meta_for(){ printf '%s/%s/%s/metadata.env\n' "$STORE" "$1" "$ARCH"; }
valid_release(){ local x; for x in "${RELEASES[@]}"; do [[ "$x" == "$1" ]] && return 0; done; return 1; }
capture(){
  local rel="$1" image="ubuntu:$1" out meta tmp cid iid digest
  valid_release "$rel" || die "unsupported v1 Ubuntu LTS release '$rel'"
  command -v "$RUNTIME" >/dev/null || die "container runtime not found: $RUNTIME"
  command -v zstd >/dev/null || die "zstd is required"
  "$RUNTIME" image inspect "$image" >/dev/null 2>&1 || die "image is not cached: $image"
  out="$(path_for "$rel")"; meta="$(meta_for "$rel")"; mkdir -p "$(dirname "$out")"
  tmp="$out.part.$$"; cid="$($RUNTIME create "$image" /bin/true)"
  trap '$RUNTIME rm -f "$cid" >/dev/null 2>&1 || true; rm -f "$tmp"' RETURN
  "$RUNTIME" export "$cid" | zstd -T0 -10 -q -o "$tmp"
  "$RUNTIME" rm "$cid" >/dev/null; cid=""
  mv "$tmp" "$out"
  iid="$($RUNTIME image inspect --format '{{.Id}}' "$image")"
  digest="$($RUNTIME image inspect --format '{{join .RepoDigests ","}}' "$image")"
  cat > "$meta" <<META
KLAB_ROOTFS_KIND=ubuntu-native
KLAB_ROOTFS_RELEASE=$rel
KLAB_ROOTFS_ARCH=$ARCH
KLAB_ROOTFS_FORMAT=oci-export-tar-zstd-v1
KLAB_ROOTFS_IMAGE=$image
KLAB_ROOTFS_IMAGE_ID=$iid
KLAB_ROOTFS_IMAGE_DIGESTS=$digest
KLAB_ROOTFS_SHA256=$(sha256sum "$out" | awk '{print $1}')
META
  trap - RETURN
  printf '%s\n' "$out"
}
status(){
  local rel out meta state sha
  printf 'RELEASE\tARCH\tSTATE\tSHA256\tPATH\n'
  for rel in "${RELEASES[@]}"; do out="$(path_for "$rel")"; meta="$(meta_for "$rel")"; state=missing; sha=-; if [[ -s "$out" && -s "$meta" ]]; then state=ready; sha="$(sha256sum "$out" | awk '{print $1}')"; fi; printf '%s\t%s\t%s\t%s\t%s\n' "$rel" "$ARCH" "$state" "$sha" "$out"; done
}
verify(){ local rel="$1" out meta expected actual; valid_release "$rel" || die "unsupported release '$rel'"; out="$(path_for "$rel")"; meta="$(meta_for "$rel")"; [[ -s "$out" && -s "$meta" ]] || die "artifact is incomplete for $rel"; expected="$(sed -n 's/^KLAB_ROOTFS_SHA256=//p' "$meta")"; actual="$(sha256sum "$out" | awk '{print $1}')"; [[ "$expected" == "$actual" ]] || die "checksum mismatch for $rel"; zstd -tq "$out"; echo "PASS ubuntu-native:$rel $actual"; }
case "${1:-}" in
  capture) shift; [[ $# == 1 ]] || die 'capture RELEASE|--all'; if [[ "$1" == --all ]]; then for r in "${RELEASES[@]}"; do capture "$r"; done; else capture "$1"; fi ;;
  verify) shift; [[ $# == 1 ]] || die 'verify RELEASE|--all'; if [[ "$1" == --all ]]; then for r in "${RELEASES[@]}"; do verify "$r"; done; else verify "$1"; fi ;;
  status) status ;;
  matrix) printf '%s\n' "${RELEASES[@]}" ;;
  *) die 'usage: klab-ubuntu-native-rootfs.sh capture|verify RELEASE|--all | status | matrix' ;;
esac
