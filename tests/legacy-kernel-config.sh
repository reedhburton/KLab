#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$root/kernel-lab.sh"

grep -Fq 'scripts/config" --file "$config" --enable "$opt"' "$source_file"
grep -Fq 'scripts/config" --file "$config" --disable "$opt"' "$source_file"
grep -Fq 'config_legacy_set "$config" "$opt" enable' "$source_file"
grep -Fq 'config_legacy_set "$config" "$opt" disable' "$source_file"
grep -Fq 'config_legacy_set "$config" "$opt" string "$val"' "$source_file"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check_config_helper() {
  local tree="$1" label="$2" config
  config="$tmp/$label.config"
  [[ -x "$tree/scripts/config" ]] || return 0
  printf '%s\n' '# CONFIG_KLAB_LEGACY_PROBE is not set' > "$config"
  "$tree/scripts/config" --file "$config" --enable CONFIG_KLAB_LEGACY_PROBE
  grep -Fxq 'CONFIG_KLAB_LEGACY_PROBE=y' "$config"
  "$tree/scripts/config" --file "$config" --disable CONFIG_KLAB_LEGACY_PROBE
  grep -Fxq '# CONFIG_KLAB_LEGACY_PROBE is not set' "$config"
  ! grep -Eq '^CONFIG_=' "$config"
  printf 'PASS: %s scripts/config accepts KLab long-form operations\n' "$label"
}

check_config_helper "${KLAB_LEGACY_TREE:-/home/reed/klab-data/cache/sources/2.6.32}" legacy-2.6.32

if [[ -n "${KLAB_MODERN_TREE:-}" ]]; then
  check_config_helper "$KLAB_MODERN_TREE" modern
else
  for candidate in /home/reed/klab-data/cache/sources/6.*; do
    if [[ -x "$candidate/scripts/config" ]]; then
      check_config_helper "$candidate" modern
      break
    fi
  done
fi

grep -Fq 'legacy_id=debian-gcc-4.1.2-amd64' "$source_file"
grep -Fq 'BASH_REMATCH[1]} <= 16' "$source_file"
grep -Fq '"$kernel_patch" == 2.*' "$source_file"
grep -Fq '"$kernel_patch" != 2.*' "$source_file"
grep -Fq 'KLAB_TOOLCHAIN_REQUESTED_VERSION:-${KLAB_TOOLCHAIN_VERSION:-}' "$source_file"
grep -Fq 'legacy_id="kernelorg-gcc-${legacy_gcc}-${hostkey}-to-${target}"' "$source_file"
grep -Fq 'nolibc[-_]' "$source_file"
grep -Fq '"$legacy_patch" == 6' "$source_file"
grep -Fq 'K8_NUMA NUMA_EMU NUMA DISCONTIGMEM' "$source_file"
grep -Fq 'configured_patch <= 10' "$source_file"
grep -Fq 'KLAB_BUILD_MAKE_ARGS+=("KCFLAGS=-fno-pie -fno-stack-protector" "KAFLAGS=-fno-pie")' "$source_file"
! grep -Fq 'KCFLAGS=-fno-pie -fno-stack-protector -mno-sse' "$source_file"
grep -Fq 'config_disable "$source" "$config" CONFIG_SECURITY_SELINUX' "$source_file"
grep -Fq 'config_disable "$source" "$config" CONFIG_RETPOLINE' "$source_file"
grep -Fq 'config_disable "$source" "$config" CONFIG_UNWINDER_ORC' "$source_file"
grep -Fq 'config_disable "$source" "$config" CONFIG_STACK_VALIDATION' "$source_file"
grep -Fq 'config_enable "$source" "$config" CONFIG_UNWINDER_FRAME_POINTER' "$source_file"
grep -Fq 'linux-2.6.12-e820-holes.patch' "$source_file"
grep -Fq 'linux-2.0.40-modern-host.patch' "$source_file"
grep -Fq 'if [ "$DEFAULT" = "-d" ]; then' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/include/asm-i386/segment.h' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/drivers/char/tty_io.c' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'debug-only global file-list walk' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'fno-strength-reduce -fno-strict-aliasing' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/fs/file_table.c' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/fs/inode.c' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'sequence this old comma expression' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq '"=&abd" (n), "=&c" (d0), "=&D" (d1), "=&S" (d2)' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'repnz; scasb\n' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq '"=&S" (d0), "=&D" (d1)' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'NO Copyright (C) 1991, 1992 Linus Torvalds' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/include/asm-i386/delay.h' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/include/asm-i386/bitops.h' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/include/asm-i386/checksum.h' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/include/asm-i386/system.h' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/arch/i386/mm/init.c' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/arch/i386/lib/checksum.c' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/arch/i386/boot/compressed/Makefile' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/arch/i386/boot/Makefile' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/arch/i386/boot/tools/build.c' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'uint32_t intel_long(uint32_t l)' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq '$(HOSTCC) $(HOSTCFLAGS) -D__BFD__ -D__BIG_KERNEL__' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
! grep -Fq 'hash $(ENCAPS)' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq '$(OBJCOPY) $(SYSTEM) $$tmppiggy' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq '"=&a"(sum), "=&c"(d0), "=&S"(d1)' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq '"=&D" (d0), "=&c" (d1)' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq '"=&a" (__d0), "=&d" (__d1)' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'adcl $0xffff, %0\n' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq '"=&c" (d0), "=&D" (d1), "=&a" (d2)' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/include/asm-i386/segment.h' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/drivers/char/tty_io.c' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'debug-only global file-list walk' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'fno-strength-reduce -fno-strict-aliasing' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/fs/file_table.c' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'a/fs/inode.c' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'sequence this old comma expression' "$root/legacy/patches/linux-2.0.40-modern-host.patch"
grep -Fq 'linux-2.2.26-memscan-string.patch' "$source_file"
grep -Fq 'repnz; scasb' "$root/legacy/patches/linux-2.2.26-memscan-string.patch"
grep -Fq 'testl %1,%1\n\tje 3f' "$root/legacy/patches/linux-2.2.26-memscan-string.patch"
grep -Fq 'printk(args)' "$root/legacy/patches/linux-2.2.26-memscan-string.patch"
grep -Fq 'a/include/asm-i386/checksum.h' "$root/legacy/patches/linux-2.2.26-memscan-string.patch"
grep -Fq 'printk(KERN_DEBUG msg)' "$root/legacy/patches/linux-2.2.26-memscan-string.patch"
grep -Fq 'BUILD_IRQ(x##y)' "$root/legacy/patches/linux-2.2.26-memscan-string.patch"
grep -Fq 'int FASTCALL(do_signal' "$root/legacy/patches/linux-2.2.26-memscan-string.patch"
grep -Fq '.klab-linux16-boot.iso' "$source_file"
grep -Fq 'boot_media=(-cdrom' "$source_file"
grep -Fq 'make_legacy_linux16_boot_iso "$build" "$build/$image_rel" "$version"' "$source_file"
grep -Fq 'linux16 /boot/vmlinuz console=ttyS0 root=/dev/ram0 ro init=/init debug vga=0xfffe' "$source_file"
grep -Fq 'legacy/minimal-init-linux20.c' "$source_file"
grep -Fq 'legacy/minimal-init-linux22.c' "$source_file"
grep -Fq 'USERSPACE_PASS' "$root/legacy/minimal-init-linux22.c"
grep -Fq 'USERSPACE_PASS' "$root/legacy/minimal-init-linux20.c"
grep -Fq 'READY 2.0.40' "$root/legacy/minimal-init-linux20.c"
grep -Fq 'upstream:v2.0.40' "$source_file"
grep -Fq -- '-cpu pentium3' "$source_file"
grep -Fq '"$configured_patch" =~ ^(0|2)$' "$source_file"
grep -Fq 'config_disable "$source" "$config" CONFIG_BLK_DEV_FD' "$source_file"
grep -Fq 'config_disable "$source" "$config" CONFIG_BLK_DEV_IDECD' "$source_file"
grep -Fq 'config_disable "$source" "$config" CONFIG_NFS_FS' "$source_file"
grep -Fq 'config_disable "$source" "$config" CONFIG_SMP' "$source_file"
grep -Fq 'e820_holes_backport=$needs_e820' "$source_file"
grep -Fq 'force_order_defs > 1' "$source_file"
grep -Fq "f.write_text(t.replace(definition, 'extern unsigned long __force_order;', 1))" "$source_file"
grep -Fq 'force_order_single_definition=$needs_force_order' "$source_file"
grep -Fq 'needs_plt32=1' "$source_file"
grep -Fq "t=t.replace(pc32, pc32+plt32, 1)" "$source_file"
grep -Fq "relocs.write_text(t)" "$source_file"
grep -Fq 'plt32_relocation_compat=$needs_plt32' "$source_file"
grep -Fq 'needs_percpu_reloc_static=1' "$source_file"
grep -Fq "t=t.replace(tentative, static, 1)" "$source_file"
grep -Fq 'percpu_reloc_static=$needs_percpu_reloc_static' "$source_file"
grep -Fq 'needs_unlzo_header_static=1' "$source_file"
grep -Fq "declaration.replace('STATIC', 'static')" "$source_file"
grep -Fq 'unlzo_header_static=$needs_unlzo_header_static' "$source_file"
grep -Fq 'needs_x86cpu_device_alias=1' "$source_file"
grep -Fq "alias='#define x86cpu_device_id x86_cpu_id" "$source_file"
grep -Fq 'x86cpu_device_alias=$needs_x86cpu_device_alias' "$source_file"
grep -Fq 'needs_i915_inline_static=1' "$source_file"
grep -Fq "'static inline bool '+helper" "$source_file"
grep -Fq 'i915_inline_static=$needs_i915_inline_static' "$source_file"
grep -Fq 'needs_acpi_osi_initdata=1' "$source_file"
grep -Fq "osi_setup_entries[OSI_STRING_ENTRIES_MAX] =" "$source_file"
grep -Fq "t.replace(inline, 'static struct osi_setup_entry osi_setup_entries', 1)" "$source_file"
grep -Fq 'acpi_osi_initdata_resident_fallback=$needs_acpi_osi_initdata' "$source_file"
grep -Fq 'for realmode_makefile in "$source/arch/x86/boot/Makefile"' "$source_file"
grep -Fq "flags+' -fno-pic'" "$source_file"
grep -Fq 'realmode_no_pic=$needs_realmode_no_pic' "$source_file"
grep -Fq 'needs_static_call_compat=1' "$source_file"
grep -Fq "x86kconfig.write_text(t.replace(inline_select, '', 1))" "$source_file"
grep -Fq 'static_call_inline_fallback=$needs_static_call_compat' "$source_file"
grep -Fq 'needs_gcc_header_fallback=1' "$source_file"
grep -Fq "numbered=sorted(compiler_gcc.parent.glob('compiler-gcc[0-9]*.h')" "$source_file"
grep -Fq 'gcc_header_fallback=$needs_gcc_header_fallback' "$source_file"
grep -Fq 'e820_hole_size' "$root/legacy/patches/linux-2.6.12-e820-holes.patch"
grep -Fq 'needs_memmap_holes=1' "$source_file"
grep -Fq 'holes[i] += (zones_size[i] * sizeof(struct page)) / PAGE_SIZE' "$source_file"
grep -Fq 'memmap_zone_holes=$needs_memmap_holes' "$source_file"
grep -Fq 'virt_to_phys((char *)MAX_DMA_ADDRESS)' "$source_file"
grep -Fq 'dma_reserve += len / PAGE_SIZE' "$source_file"
grep -Fq 'holes[ZONE_DMA] += dma_reserve' "$source_file"
grep -Fq 'dma_zone_reserve=$needs_memmap_holes' "$source_file"
grep -Fq 'HOSTCFLAGS=-fno-pie -no-pie -fgnu89-inline -include limits.h -include locale.h' "$source_file"
grep -Fq 'if [[ "$kernel_major" == 2 ]]; then' "$source_file"
grep -Fq 'Linux 3.x/4.x supply generated architecture include paths' "$source_file"
grep -Fq 'needs_extract_overlap=1' "$source_file"
grep -Fq 'if (offs < olen)' "$source_file"
grep -Fq 'for (i = ehdr.e_phnum - 1; i >= 0; i--)' "$source_file"
grep -Fq '"$version" =~ ^v3\.([2-9]|1[0-9])$' "$source_file"
grep -Fq 'affected_x86_mapping=' "$source_file"
grep -Fq 'affected_x86_elf=' "$source_file"
grep -Fq "if misc.exists():" "$source_file"
grep -Fq "'z_run_size' not in t and rounding in t" "$source_file"
grep -Fq 'affected_x86_overlap=parts[0] == 3 and 18 <= parts[1] <= 19' "$source_file"
grep -Fq 'if (offs < 8*1024*1024)' "$source_file"
grep -Fq '(12|13|14)$ ]] && needs_memmap_holes=1' "$source_file"
grep -Fq 'legacy_sublevel >= 31 && legacy_sublevel <= 34' "$source_file"
grep -Fq 'config_value "$source" "$config" CONFIG_NR_CPUS 2' "$source_file"
grep -Fq '2.6.16*)' "$source_file"
grep -Fq 'KLAB_INSMOD_DETACHED' "$source_file"
grep -Fq '2.0.*|2.2.*|2.6.16*) dmesg | tail -n 80 || dmesg || true' "$source_file"
[[ "$(grep -Fc '"$target" == upstream:v2.6.16 && "$ARCH" == x86_64' "$source_file")" == 2 ]]
grep -Fq '2.6.16*) use_live_parameter=0' "$root/tests/all-five/workload.sh"
grep -Fq '"^$module_name " /proc/modules' "$source_file"
grep -Fq 'for opt in NETFILTER IPV6 WIRELESS CFG80211 MAC80211 HAMRADIO DRM SOUND SND MEDIA_SUPPORT USB_SUPPORT USB SCSI ATA PCCARD EXT4_FS NFS_FS NFSD CIFS XFS_FS BTRFS_FS REISERFS_FS JFS_FS FUSE_FS AUTOFS4_FS SECURITY_SELINUX SECURITY_SMACK SECURITY_TOMOYO SECURITY_APPARMOR FTRACE TRACING BLK_DEV_MD MD INPUT HID ACPI PROFILING PERF_EVENTS KPROBES NET_VENDOR_3COM NET_VENDOR_ADAPTEC NET_VENDOR_AGERE NET_VENDOR_ALTEON NET_VENDOR_AMD NET_VENDOR_ARC NET_VENDOR_ATHEROS NET_VENDOR_BROADCOM NET_VENDOR_BROCADE NET_VENDOR_CHELSIO NET_VENDOR_CISCO NET_VENDOR_DEC NET_VENDOR_DLINK NET_VENDOR_EMULEX NET_VENDOR_EXAR NET_VENDOR_HP NET_VENDOR_I825XX NET_VENDOR_MARVELL NET_VENDOR_MELLANOX NET_VENDOR_MICREL NET_VENDOR_MYRI NET_VENDOR_NATSEMI NET_VENDOR_8390 NET_VENDOR_NVIDIA NET_VENDOR_OKI NET_VENDOR_QLOGIC NET_VENDOR_QUALCOMM NET_VENDOR_REALTEK NET_VENDOR_RDC NET_VENDOR_SAMSUNG NET_VENDOR_SEEQ NET_VENDOR_SILAN NET_VENDOR_SIS NET_VENDOR_SMSC NET_VENDOR_STMICRO NET_VENDOR_SUN NET_VENDOR_TEHUTI NET_VENDOR_TI NET_VENDOR_VIA NET_VENDOR_WIZNET' "$source_file"
grep -Fq 'config_enable "$source" "$config" CONFIG_CC_OPTIMIZE_FOR_SIZE' "$source_file"
grep -Fq 'needs_bootdata_mapping=1' "$source_file"
grep -Fq 'retain loader mappings until boot inputs are copied' "$source_file"
grep -Fq 'early_make_pgtable((unsigned long)__va(read_cr3()))' "$source_file"
grep -Fq 'early_make_pgtable((unsigned long)__va(0))' "$source_file"
grep -Fq 'make the early page-table BRK buffer writable' "$source_file"
grep -Fq 'early_make_pgtable((unsigned long)__va(base))' "$source_file"
grep -Fq '"$configured_version" =~ ^(3|4)$' "$source_file"
grep -Fq 'for opt in MICROCODE MICROCODE_INTEL MICROCODE_AMD' "$source_file"
python3 - <<'PYOVERLAP'
# Reproduce the v3.16 failing layout: the old offset (0x92c000) places
# running decompressor code inside the expanded 15,247,544-byte image.
olen=15247544
old=0x92c000
new=(olen+4095)&~4095
assert old < olen
assert new >= olen
assert new % 4096 == 0
PYOVERLAP
grep -Fq 'ARCH=x86 selects i386_defconfig' "$source_file"
grep -Fq "vdso64=p.parent/'arch/x86_64/vdso/Makefile'" "$source_file"
grep -Fq 'legacy_guest_busybox_target "$requested_target"' "$source_file"
! grep -Fq "compressed_misc=p.parent/'arch/x86/boot/compressed/misc.c'" "$source_file"
grep -Fq '__attribute__((used)) __sched' "$source_file"
grep -Fq 'setup_upstream_build_toolchain "$arch" "$source"' "$source_file"
grep -Fq '(( ${kernel_patch%%.*} <= 10 ))' "$source_file"
grep -Fq "grep -Fq 'defined(@' \"\$source/kernel/timeconst.pl\"" "$source_file"
grep -Fq 'KLAB_BUILD_MAKE_ARGS+=("PERL=$SELF_DIR/lib/legacy-kernel-perl")' "$source_file"
grep -Fq '"$target" == upstream:v2.*' "$source_file"
grep -Fq 'ACTIVE_USERSPACE_ARTIFACT="$(ensure_legacy_guest_busybox "$ARCH")"' "$source_file"
legacy_tc=/home/reed/klab-data/artifacts/toolchains/kernelorg-gcc-4.9.4-x86_64-to-x86_64-linux
if [[ -f "$legacy_tc/.klab-resolver.env" ]]; then
  unset KLAB_TOOLCHAIN_CC
  source "$legacy_tc/.klab-resolver.env"
  [[ "$($KLAB_TOOLCHAIN_CC -dumpfullversion -dumpversion)" == 4.9.4 ]]
  [[ "$($KLAB_TOOLCHAIN_CC -dumpmachine)" == x86_64-linux ]]
fi

legacy_perl="$root/lib/legacy-kernel-perl"
[[ -x "$legacy_perl" ]]
timeconst=/home/reed/klab-data/cache/sources/2.6.32.71/kernel/timeconst.pl
if [[ -f "$timeconst" ]]; then
  "$legacy_perl" "$timeconst" 250 > "$tmp/timeconst.h"
  grep -Fq 'HZ_TO_MSEC_MUL32' "$tmp/timeconst.h"
fi


# Linux before the x86 architecture merge must retain split source layouts.
grep -Fq 'linux_karch_for_source "$arch" "$source"' "$source_file"
grep -Fq 'arch/x86_64/boot/bzImage' "$source_file"
grep -Fq 'arch/i386/boot/bzImage' "$source_file"
grep -Fq 'linux_defconfig_for_source "$arch" "$source"' "$source_file"
grep -Fq 'prepare_legacy_make_compat_source "$source" "$version"' "$source_file"
grep -Fq 'schema=klab-legacy-source-compat-v65' "$source_file"
grep -Fq "s=re.sub(r'(?m)^config %config:" "$source_file"
grep -Fq 'ensure_legacy_base64()' "$source_file"
grep -Fq 'legacy/klab-base64.c' "$source_file"
grep -Fq 'linux_kernel_image_rel_for_build "$build" "$ARCH"' "$source_file"
grep -Fq 'karch="$(linux_karch_for_build "$build" "$ARCH")"' "$source_file"
grep -Fq 'karch="$(linux_karch_for_source "$ARCH" "$BUNDLE_SOURCE_DIR")"' "$source_file"

grep -Fq 'external_module_make_assignment()' "$source_file"
grep -Fq 'printf "SUBDIRS=%s\n" "$module_dir"' "$source_file"
grep -Fq 'if [[ "$ext_assignment" == M=* ]]' "$source_file"
grep -Fq 'rel=arch/i386/boot/bzImage' "$source_file"
grep -Fq 'rel=arch/x86_64/boot/bzImage' "$source_file"
grep -Fq 'HOSTCC=$(command -v gcc)' "$source_file"
grep -Fq 'KERNEL_MIN_VERSION=2.0' "$root/architectures/i386.conf"
grep -Fq 'set_inode_field /dev/console mode 020600' "$source_file"
grep -Fq 'set_inode_field /dev/null mode 020666' "$source_file"
grep -Fq 'set_inode_field /dev/ttyS1 mode 020600' "$source_file"
grep -Fq 'POSIX read has no timeout option' "$source_file"
grep -Fq 'if ! IFS= read -r line <&3; then' "$source_file"
grep -Fq 'ensure_linux24_guest_busybox()' "$source_file"
grep -Fq 'Buildroot BusyBox contains PT_TLS' "$source_file"
grep -Fq 'CONFIG_FEATURE_2_4_MODULES=y' "$source_file"
grep -Fq 'install_busybox_linux24_patch()' "$source_file"
grep -Fq '__NR_query_module' "$root/legacy/patches/busybox-1.37-linux24-musl-module-syscalls.patch"
grep -Fq 'upstream:v2.[0-5].*' "$source_file"
grep -Fq 'build_linux24_external_modules()' "$source_file"
grep -Fq 'kernel_image_rel="$(cat "$dest/build/.klab-image-rel"' "$root/klab-bundle.sh"
grep -Fq 'for m in /test/modules/*.ko /test/modules/*.o' "$source_file"

printf '%s\n' 'PASS: legacy kernel configuration, compiler, Perl adapter, and split x86 layout'

grep -Fq 'ext_assignment="$(external_module_make_assignment "$BUNDLE_SOURCE_DIR" "$job/module")"' "$source_file"


# One-shot module/process tests must convert their CPIO tree to an ext2 ramdisk
# and use init=/init for Linux 2.0 through 2.4.
grep -Fq 'legacy_root="${initrd%.cpio.gz}.root"' "$root/kernel-lab.sh"
grep -Fq 'root=/dev/ram0 rw init=/init' "$root/kernel-lab.sh"
# Linux 2.4 predates reliable sysfs NIC discovery; retain the requested iface
# only when /sys/class/net is unavailable.
grep -Fq "[ ! -r /sys/class/net/'\$iface'/address ] && { echo '\$iface'; exit 0; }" "$root/kernel-lab.sh"


grep -Fq 'make_legacy_linux16_runtime_iso()' "$source_file"
grep -Fq 'legacy_iso="$dir/runtime-linux16.iso"' "$source_file"
grep -Fq 'test_boot_media=(-cdrom "$legacy_test_iso" -boot d)' "$source_file"


grep -Fq 'ensure_linux22_guest_busybox()' "$source_file"
grep -Fq 'legacy-ssh/linux20-glibc21-dropbear044/i386/rootfs.tar' "$source_file"
grep -Fq 'if ! "$guest_bb" base64 --help' "$source_file"
grep -Fq 'wc ifconfig route ping test expr true false \[ echo printf kill hostname ps netstat' "$source_file"

grep -Fq 'used_kib="$(du -sk "$root" | awk' "$source_file"
