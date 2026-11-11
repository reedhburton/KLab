#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/kernel-lab.sh"
grep -Fq 'config_value "$source" "$config" CONFIG_BLK_DEV_RAM_SIZE 32768' "$f"
grep -Fq 'NETDEVICES NET_ETHERNET EEXPRESS_PRO100 NE2K_PCI' "$f"
grep -Fq 'NETDEVICES NET_ETHERNET NET_ISA NE2000' "$f"
grep -Fq "elif mode=='value': lines.append(opt+'='+value)" "$f"
patch="$ROOT/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq '__generic_memcpy_tofs(to, from, n);' "$patch"
grep -Fq '__generic_memcpy_fromfs(to, from, n);' "$patch"
grep -Fq -- '-fno-strict-aliasing' "$patch"
grep -Fq 'first_file = file;' "$patch"
grep -Fq 'first_inode = inode;' "$patch"
bash -n "$f"
echo 'PASS: Linux 2.0/2.2 legacy SSH RAM disk and QEMU NIC configuration'
