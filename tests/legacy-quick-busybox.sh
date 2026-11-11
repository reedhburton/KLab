#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
source_file="$ROOT/kernel-lab.sh"
grep -Fq "busybox-legacy-buildroot/%s/busybox" "$source_file"
grep -Fq 'rootfs="$(ensure_buildroot_profile "$arch" minimal)"' "$source_file"
grep -Fq 'tar -xOf "$rootfs" ./bin/busybox > "$tmp"' "$source_file"
grep -Fq 'validate_guest_busybox "$arch" "$tmp"' "$source_file"
grep -Fq 'buildroot:%s/minimal' "$source_file"
! grep -Fq 'busybox.net/downloads/binaries/1.21.1' "$source_file"

for arch in x86_64 i386; do
  rootfs="/home/reed/klab-data/artifacts/userspaces/buildroot/2025.02.18/minimal/$arch/rootfs.tar"
  [[ -f "$rootfs" ]] || continue
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  tar -xOf "$rootfs" ./bin/busybox > "$tmp"
  chmod 0755 "$tmp"
  file "$tmp" | grep -Fq 'statically linked'
  case "$arch" in
    x86_64) file "$tmp" | grep -Fq 'x86-64' ;;
    i386) file "$tmp" | grep -Eq 'Intel 80386|32-bit' ;;
  esac
  rm -f "$tmp"
  trap - EXIT
done
echo 'legacy quick BusyBox model: PASS'
