#!/usr/bin/env bash
set -euo pipefail
KLAB_ROOT="${KLAB_ROOT:-$HOME/klab}"
RUNTIME="${KLAB_CONTAINER_RUNTIME:-docker}"
RELEASES="${KLAB_UBUNTU_CATALOG_RELEASES:-16.04 18.04 20.04 22.04 24.04 26.04}"
OUT="${1:-ubuntu-generic-kernel-catalog.tsv}"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
printf 'release\tkernel\tflavor\tpackage\twarehouse\n' >"$OUT"
for rel in $RELEASES; do
  image="ubuntu:$rel"
  "$RUNTIME" image inspect "$image" >/dev/null 2>&1 || "$RUNTIME" pull --platform linux/amd64 "$image" >/dev/null
  "$RUNTIME" run --rm --platform linux/amd64 "$image" /bin/sh -ec '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update >/dev/null
    apt-cache pkgnames | LC_ALL=C grep -E "^linux-image-[0-9]+[.][0-9]+[.][0-9]+-[0-9]+-generic$" | LC_ALL=C sort -Vu
  ' >"$tmp"
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue; krel="${pkg#linux-image-}"
    state=MISSING; [[ -f "$KLAB_ROOT/targets/kernels/ubuntu/$rel/x86_64/$krel/bundle.env" ]] && state=LOCAL
    printf '%s\t%s\tgeneric\t%s\t%s\n' "$rel" "$krel" "$pkg" "$state" >>"$OUT"
  done <"$tmp"
  [[ "${KLAB_CATALOG_KEEP_IMAGES:-0}" == 1 ]] || "$RUNTIME" image rm "$image" >/dev/null 2>&1 || true
done
printf '%s\n' "$OUT"
