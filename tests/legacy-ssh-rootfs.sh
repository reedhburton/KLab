#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/klab-legacy-ssh-rootfs.sh"
bash -n "$f"
for token in '2.0.30' '0.60.2-3.1' '2.1.3-25' '0.44+final-1' 'KLAB_LEGACY_SSH_ROOTFS_SHA256' 'dropbear -F -E -s'; do grep -Fq "$token" "$f"; done
echo 'PASS: pinned Linux 2.0-era SSH rootfs recipe'
grep -Fq 'sash_2.1-5.deb' "$f"
grep -Fq 'netbase_3.11-1.2.deb' "$f"
grep -Fq 'legacy-ssh-init-linux20.c' "$f"
grep -Fq 'init-linux20.bin' "$f"
grep -Fq 'root:/root:/bin/sash' "$f"
grep -Fq 'libc6_2.0.7.19981211-6.deb' "$f"
grep -Fq '/lib20/ld-linux.so.2' "$ROOT/legacy/legacy-ssh-init-linux20.c"
grep -Fq "printf '%s\n' /bin/sash > \"\$root/etc/shells\"" "$f"
grep -Fq '"add","-net","10.0.2.0","netmask","255.255.255.0","dev","eth0"' "$ROOT/legacy/legacy-ssh-init-linux20.c"
grep -Fq '"add","default","gw","10.0.2.2"' "$ROOT/legacy/legacy-ssh-init-linux20.c"
grep -Fq 'init=/init-linux20.bin' "$ROOT/tools/klab-legacy-ssh-iso.sh"
