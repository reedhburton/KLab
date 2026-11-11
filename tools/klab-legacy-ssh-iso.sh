#!/usr/bin/env bash
set -Eeuo pipefail
raw_initrd=0
root_disk=
case ${1:-} in
  --raw-initrd) raw_initrd=1; shift ;;
  --root-disk) [[ $# -ge 2 ]] || { echo "--root-disk requires an output path" >&2; exit 2; }; root_disk="$2"; shift 2 ;;
esac
[[ $# == 4 ]] || { echo "usage: $0 [--raw-initrd | --root-disk OUTPUT.img] KERNEL ROOTFS_TAR AUTHORIZED_KEY.pub OUTPUT.iso" >&2; exit 2; }
kernel="$1" rootfs="$2" pubkey="$3" output="$4"
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; source "$SELF/lib/klab-root.sh"; klab_root_ensure_layout
work="$(mktemp -d)"; trap "rm -rf '$work'" EXIT
mkdir -p "$work/root" "$work/iso/boot/grub"; tar -C "$work/root" -xf "$rootfs"
install -m 600 "$pubkey" "$work/root/root/.ssh/authorized_keys"
if (( raw_initrd )); then initrd_size=16M; else initrd_size=24M; fi
truncate -s "$initrd_size" "$work/initrd.ext2"
mkfs.ext2 -q -F -r 0 -b 1024 -I 128 -O none -m 0 -d "$work/root" "$work/initrd.ext2"
console_node='mknod console c 5 1'
[[ -z "$root_disk" ]] || console_node='mknod console c 4 0'
{ printf '%s\n' 'cd /dev' "$console_node" 'mknod null c 1 3' 'mknod tty1 c 4 1' 'mknod random c 1 9' 'mknod urandom c 1 9' 'mknod ttyS0 c 4 64' 'set_inode_field /dev/console mode 020600' 'set_inode_field /dev/null mode 020666' 'set_inode_field /dev/tty1 mode 020600' 'set_inode_field /dev/random mode 020666' 'set_inode_field /dev/urandom mode 020666' 'set_inode_field /dev/ttyS0 mode 020600' 'set_inode_field /root uid 0' 'set_inode_field /root gid 0' 'set_inode_field /root/.ssh uid 0' 'set_inode_field /root/.ssh gid 0' 'set_inode_field /root/.ssh/authorized_keys uid 0' 'set_inode_field /root/.ssh/authorized_keys gid 0'; } | debugfs -w "$work/initrd.ext2" >/dev/null 2>&1
e2fsck -fy "$work/initrd.ext2" >/dev/null
e2fsck -fn "$work/initrd.ext2" >/dev/null
cp "$kernel" "$work/iso/boot/vmlinuz"
if [[ -n "$root_disk" ]]; then
  mkdir -p "$(dirname "$root_disk")"
  cp "$work/initrd.ext2" "$root_disk"
  cat > "$work/iso/boot/grub/grub.cfg" <<'GRUB'
serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
terminal_input serial
terminal_output serial
set timeout=0
menuentry 'KLab historical SSH' {
 linux16 /boot/vmlinuz root=/dev/hda rw init=/init-linux20.bin debug vga=0xfffe
 boot
}
GRUB
else
  if (( raw_initrd )); then
    cp "$work/initrd.ext2" "$work/iso/boot/initrd.img"
  else
    gzip -1c "$work/initrd.ext2" > "$work/iso/boot/initrd.img"
  fi
  cat > "$work/iso/boot/grub/grub.cfg" <<'GRUB'
serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
terminal_input serial
terminal_output serial
set timeout=0
menuentry 'KLab historical SSH' {
 linux16 /boot/vmlinuz console=ttyS0 root=/dev/ram0 rw init=/init ramdisk_size=32768 debug vga=0xfffe
 initrd16 /boot/initrd.img
 boot
}
GRUB
fi
tools="$KLAB_ARTIFACTS/host-tools/xorriso/root"; tool_path="$PATH"; tool_lib="${LD_LIBRARY_PATH:-}"
if ! command -v xorriso >/dev/null || ! command -v mformat >/dev/null; then tool_path="$tools/usr/bin:$tool_path"; tool_lib="$tools/usr/lib/x86_64-linux-gnu${tool_lib:+:$tool_lib}"; fi
mkdir -p "$(dirname "$output")"; PATH="$tool_path" LD_LIBRARY_PATH="$tool_lib" grub-mkrescue -o "$output" "$work/iso" >/dev/null 2>&1
sha256sum "$output"
