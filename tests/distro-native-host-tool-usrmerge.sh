#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
f="$ROOT/lib/buildenv-capture.sh"
grep -Fq 'dpkg_path=${resolved#/usr}' "$f"
grep -Fq 'dpkg-query -S "$dpkg_path"' "$f"
# Debian bookworm records dash as /bin/dash although /bin/sh resolves through /usr/bin.
rt="${KLAB_CONTAINER_RUNTIME:-}"
if [[ -z "$rt" ]]; then
  command -v podman >/dev/null 2>&1 && rt=podman || command -v docker >/dev/null 2>&1 && rt=docker || true
fi
if [[ -z "$rt" ]]; then
  echo 'distro-native host-tool usrmerge ownership: SKIP (no podman/docker)'
  exit 0
fi
"$rt" run --rm debian:bookworm-slim sh -lc 'set -eu; r=$(readlink -f /bin/sh); test "$r" = /usr/bin/dash; ! dpkg-query -S "$r" >/dev/null 2>&1; dpkg-query -S "${r#/usr}" | grep -q "^dash:"'
echo 'distro-native host-tool usrmerge ownership: PASS'
