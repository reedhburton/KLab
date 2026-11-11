#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/klab-buildenv.sh"
grep -Fq 'if [ "${11}" = fedora ]; then' "$f" || {
  echo 'Fedora buildenv validator must address positional parameter 11 with braces' >&2
  exit 1
}
if grep -Fq 'if [ "$11" = fedora ]; then' "$f"; then
  echo 'unbraced $11 would expand as $1 followed by literal 1 under POSIX sh' >&2
  exit 1
fi
/bin/sh -eu -c 'set -- a b c d e f g h i j fedora; [ "${11}" = fedora ]'
echo 'fedora-binutils-provider-positional: PASS'
