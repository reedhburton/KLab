#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
for x in python3 tar zstd sha256sum dirname mkdir; do ln -s "$(command -v "$x")" "$T/bin/$x"; done
# Podman is intentionally irrelevant for format v1: run-module uses bwrap.
ln -s /bin/true "$T/bin/podman"
if PATH="$T/bin" /bin/bash "$ROOT/klab-buildenv.sh" doctor >/dev/null 2>&1; then
  echo 'FAIL: buildenv doctor accepted podman without bwrap' >&2; exit 1
fi
ln -s /bin/true "$T/bin/bwrap"
PATH="$T/bin" /bin/bash "$ROOT/klab-buildenv.sh" doctor >/dev/null
echo 'buildenv-doctor: PASS'
