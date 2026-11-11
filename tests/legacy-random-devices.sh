#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/kernel-lab.sh"
grep -Fq '[ -c /dev/random ] || /bin/busybox mknod /dev/random c 1 8' "$F"
grep -Fq '[ -c /dev/urandom ] || /bin/busybox mknod /dev/urandom c 1 9' "$F"
grep -Fq "'mknod random c 1 8'" "$F"
grep -Fq "'mknod urandom c 1 9'" "$F"
grep -Fq "'set_inode_field /dev/random mode 020666'" "$F"
grep -Fq "'set_inode_field /dev/urandom mode 020666'" "$F"
bash -n "$F"
echo 'PASS: pre-devtmpfs session roots provide random devices for static SSH'

for node in null random urandom; do
  grep -Fq "[ ! -e /dev/$node ] || [ -c /dev/$node ] || rm -f /dev/$node" "$ROOT/kernel-lab.sh"
done

# Redirecting mknod errors to /dev/null would recreate the just-removed
# placeholder as a regular file before mknod executes.
grep -Fq 'mknod /dev/null c 1 3 2>/tmp/klab-mknod.err' "$ROOT/kernel-lab.sh"
! grep -Fq 'mknod /dev/null c 1 3 2>/dev/null' "$ROOT/kernel-lab.sh"
