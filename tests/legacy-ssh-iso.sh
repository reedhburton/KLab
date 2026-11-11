#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; f="$ROOT/tools/klab-legacy-ssh-iso.sh"
bash -n "$f"
for t in 'mkfs.ext2 -q -F -r 0' 'e2fsck -fy' 'e2fsck -fn' '--root-disk OUTPUT.img' 'root=/dev/hda rw init=/init-linux20.bin' 'ramdisk_size=32768' 'authorized_keys uid 0' 'mknod random c 1 9'; do grep -Fq -- "$t" "$f"; done
echo 'PASS: historical SSH ISO assembly is deterministic and rootless'
