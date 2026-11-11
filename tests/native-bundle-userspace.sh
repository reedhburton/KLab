#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/klab-bundle.sh"
bash -n "$f"
grep -Fq 'native:ubuntu:*|native:debian:*|native:fedora:*|native:centos:*|native:alpine:*|native:arch:*) echo "$1"' "$f"
grep -Fq 'native-rootfs.tar.zst' "$f"
grep -Fq '"kind":"native"' "$f"
grep -Fq 'BUNDLE_GUEST_USERSPACE_SPEC=native:$native_provider:$native_release' "$f"
grep -Fq 'native guest rootfs checksum mismatch' "$f"
grep -Fq 'native guest metadata checksum mismatch' "$f"
echo 'PASS native .klab userspace create/import wiring'
