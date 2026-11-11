#!/usr/bin/env bash
set -Eeuo pipefail

# KLAB_UNIFIED_ROOT_R22
# KLAB_NATIVE_PATHS_R23
# KLAB_RESIDUAL_PATH_AUDIT_R24
_KLAB_SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [[ -f "$_KLAB_SELF_DIR/lib/klab-root.sh" ]]; then
  # shellcheck source=lib/klab-root.sh
  source "$_KLAB_SELF_DIR/lib/klab-root.sh"
  klab_root_ensure_layout
fi
unset _KLAB_SELF_DIR

# kernel-lab.sh - backend-aware kernel/module compatibility lab.
# v15: usability/scaling/extensibility pass. Architecture profiles are data-driven;
# test-set supports bounded workers; arbitrary prepared Linux kernels can be registered;
# Buildroot SDKs are exposed for general cross compilation. Strict offline Buildroot
# source-cache behavior from v14 remains unchanged.

LAB_HOME="$KLAB_ROOT"
SRC="$KLAB_CACHE/linux"
SOURCES="$KLAB_CACHE/sources"
BUILDS="$KLAB_WORK/builds"
INITRAMFS="$KLAB_WORK/initramfs"
LOGS="$KLAB_RESULTS/logs"
EXAMPLES="$KLAB_STATE/examples"
KERNELS="$KLAB_TARGETS/kernels"
TOOLCHAINS="$KLAB_TOOLCHAIN_STORE"
JOBS_ROOT="$KLAB_WORK/jobs"
SESSIONS="$KLAB_WORK/sessions"
ARTIFACTS="$KLAB_ARTIFACTS"
CRASHES="$KLAB_RESULTS/crashes"
EXPORTS="$KLAB_TRANSFER/exports"
GUESTS="$KLAB_USERSPACE_STORE"
BUILDROOT_HOME="$KLAB_WORK/buildroot"
BUILDROOT_VERSION="${KLAB_BUILDROOT_VERSION:-2025.02.18}"
BUILDROOT_URL_BASE="${KLAB_BUILDROOT_URL_BASE:-https://buildroot.org/downloads}"
BUILDROOT_SRC="$BUILDROOT_HOME/src/buildroot-$BUILDROOT_VERSION"
BUILDROOT_DL="$BUILDROOT_HOME/dl"
BUILDROOT_OUT="$BUILDROOT_HOME/output"
BUILDROOT_OFFLINE_SITE="$BUILDROOT_HOME/offline-primary"
BUILDROOT_CACHE_ONLY="${KLAB_BUILDROOT_CACHE_ONLY:-}"
DROPBEAR_VERSION="${KLAB_DROPBEAR_VERSION:-2026.93}"
DROPBEAR_SHA256="${KLAB_DROPBEAR_SHA256:-310a6087952897c182efbe16088fa0c4d07c467e850a22699472137278fabf09}"
USERSPACE_REQUESTED="${KLAB_USERSPACE:-auto}"
ACTIVE_USERSPACE_SPEC="busybox-static"
ACTIVE_USERSPACE_ARTIFACT=""
MODE_FILE="$KLAB_STATE/MODE"
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SELF_PATH="$(readlink -f "$0" 2>/dev/null || printf '%s/%s' "$SELF_DIR" "$(basename "$0")")"
ARCH_PROFILES_DIR="${KLAB_ARCH_PROFILES_DIR:-$SELF_DIR/architectures}"
ARCH_MODEL_BIN="${KLAB_ARCH_MODEL_BIN:-$SELF_DIR/lib/arch-model.sh}"
[[ -f "$ARCH_MODEL_BIN" ]] || { echo "kernel-lab: ERROR: architecture model missing: $ARCH_MODEL_BIN" >&2; exit 1; }
# shellcheck source=lib/arch-model.sh
source "$ARCH_MODEL_BIN"
BUNDLE_BIN="${KLAB_BUNDLE_BIN:-$SELF_DIR/klab-bundle.sh}"
TOOLCHAIN_BOUNDARY_BIN="${KLAB_TOOLCHAIN_BOUNDARY_BIN:-$SELF_DIR/klab-toolchain-boundary.sh}" # KLAB_TOOLCHAIN_RUNTIME_BOUNDARY_M2
BUILDENV_BIN="${KLAB_BUILDENV_BIN:-$SELF_DIR/klab-buildenv.sh}" # KLAB_BUILDENV_M2
DISTRO_TOOLCHAIN_BIN="${KLAB_DISTRO_TOOLCHAIN_BIN:-$SELF_DIR/klab-distro-toolchain.sh}"
ARCH_REQUESTED="${KLAB_ARCH:-x86_64}"
ARCH="x86_64"
CONTAINER_RUNTIME="${KLAB_CONTAINER_RUNTIME:-}"
INCLUDE_DISTRO_MODULES="${KLAB_INCLUDE_DISTRO_MODULES:-0}"
OFFLINE="${KLAB_OFFLINE:-}"
ALLOW_TOOLCHAIN_OVERRIDE="${KLAB_ALLOW_TOOLCHAIN_OVERRIDE:-0}"
TOOLCHAIN_OVERRIDE_CC="${KLAB_CC:-}"
STABLE_URL="${KLAB_STABLE_URL:-https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git}"
MAINLINE_URL="${KLAB_MAINLINE_URL:-https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git}"
CROSSTOOL_BASE_URL="${KLAB_CROSSTOOL_BASE_URL:-https://www.kernel.org/pub/tools/crosstool/files/bin}"
FREEBSD_DOWNLOAD_BASE="${KLAB_FREEBSD_DOWNLOAD_BASE:-https://download.freebsd.org}"
JOBS="${KLAB_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
MEMORY="${KLAB_MEMORY:-1024M}"
NATIVE_MEMORY="${KLAB_NATIVE_MEMORY:-8192M}"
CPUS="${KLAB_CPUS:-2}"
BOOT_TIMEOUT="${KLAB_BOOT_TIMEOUT:-90}"
CRASHDUMP_FORMAT="${KLAB_CRASHDUMP_FORMAT:-elf}"
QEMU_OVERRIDE="${KLAB_QEMU:-}"
BUSYBOX_OVERRIDE="${KLAB_BUSYBOX:-}"
BUSYBOX_SUITE="${KLAB_BUSYBOX_SUITE:-trixie}"

# KLAB_OFFLINE explicitly overrides the persistent lab role. Otherwise the role
# written by `kernel-lab init --offline|--staging` is used.
if [[ -z "$OFFLINE" ]]; then
  if [[ -f "$MODE_FILE" ]] && [[ "$(cat "$MODE_FILE" 2>/dev/null || true)" == offline ]]; then OFFLINE=1; else OFFLINE=0; fi
fi

say() { printf '\n==> %s\n' "$*" >&2; }
die() { printf 'kernel-lab: ERROR: %b\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

ARCH_E2E_BIN="${KLAB_ARCH_E2E_BIN:-$SELF_DIR/lib/arch-e2e.sh}"
[[ -f "$ARCH_E2E_BIN" ]] || die "architecture E2E helper missing: $ARCH_E2E_BIN"
# shellcheck source=lib/arch-e2e.sh
source "$ARCH_E2E_BIN"

SCENARIO_BIN="${KLAB_SCENARIO_BIN:-$SELF_DIR/lib/test-scenario.sh}"
[[ -f "$SCENARIO_BIN" ]] || die "scenario runner helper missing: $SCENARIO_BIN"
# shellcheck source=lib/test-scenario.sh
source "$SCENARIO_BIN"

MULTIGUEST_BIN="${KLAB_MULTIGUEST_BIN:-$SELF_DIR/lib/multiguest-scenario.sh}"
[[ -f "$MULTIGUEST_BIN" ]] || die "multi-guest scenario runner helper missing: $MULTIGUEST_BIN"
# shellcheck source=lib/multiguest-scenario.sh
source "$MULTIGUEST_BIN"

arch_profile_files() { klab_arch_profile_files; }
architecture_ids() { klab_arch_ids; }
arch_profile_field() { klab_arch_profile_field "$1" "$2"; }
canonical_arch() {
  local a
  a="$(klab_arch_canonical "$1" 2>/dev/null || true)"
  [[ -n "$a" ]] || die "unsupported architecture '$1'; run '$0 architectures' to list installed profiles"
  printf '%s\n' "$a"
}
set_active_arch() {
  local a status
  a="$(canonical_arch "$1")"; status="$(klab_arch_status "$a")"
  if ! klab_arch_assert_enabled "$a"; then
    if [[ "$status" == experimental ]]; then
      die "architecture '$a' is experimental; set KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 to enable execution/build operations"
    fi
    die "architecture '$a' is disabled by its profile"
  fi
  ARCH="$a"
}
host_arch() { klab_arch_host; }

arch_value_or_fallback() {
  local arch="$(canonical_arch "$1")" field="$2" fallback="$3" value=""
  value="$(arch_profile_field "$arch" "$field" 2>/dev/null || true)"
  [[ -n "$value" ]] && printf '%s\n' "$value" || printf '%s\n' "$fallback"
}

linux_karch() {
  local a="$(canonical_arch "$1")" v
  v="$(klab_arch_kernel_arch "$a" 2>/dev/null || true)"; [[ -n "$v" ]] && { printf '%s\n' "$v"; return; }
  arch_value_or_fallback "$a" KERNEL_ARCH "$(case "$a" in x86_64|i386) echo x86 ;; aarch64) echo arm64 ;; armv7) echo arm ;; mips*) echo mips ;; esac)"
}
linux_defconfig() {
  local a="$(canonical_arch "$1")"
  arch_value_or_fallback "$a" KERNEL_DEFCONFIG "$(case "$a" in x86_64) echo x86_64_defconfig ;; i386) echo i386_defconfig ;; aarch64) echo defconfig ;; armv7) echo multi_v7_defconfig ;; mips*) echo malta_defconfig ;; esac)"
}
linux_kernel_image_rel() {
  local a="$(canonical_arch "$1")"
  arch_value_or_fallback "$a" KERNEL_IMAGE "$(case "$a" in x86_64|i386) echo arch/x86/boot/bzImage ;; aarch64) echo arch/arm64/boot/Image ;; armv7) echo arch/arm/boot/zImage ;; mips*) echo vmlinux ;; esac)"
}
# Before Linux 2.6.24, 32-bit and 64-bit x86 used separate source
# architecture directories. Derive the make ARCH and image path from the actual
# immutable source tree instead of guessing solely from the user-facing arch.
linux_karch_for_source() {
  local a="$(canonical_arch "$1")" source="$2"
  if [[ ! -d "$source/arch/x86" ]]; then
    case "$a" in
      x86_64) [[ -d "$source/arch/x86_64" ]] && { printf '%s\n' x86_64; return; } ;;
      i386) [[ -d "$source/arch/i386" ]] && { printf '%s\n' i386; return; } ;;
    esac
  elif [[ "$a" == x86_64 || "$a" == i386 ]]; then
    # Unified arch/x86 trees still require the user-facing x86 width as ARCH;
    # ARCH=x86 selects i386_defconfig in several 3.x releases.
    printf '%s\n' "$a"
    return
  fi
  linux_karch "$a"
}
linux_kernel_image_rel_for_source() {
  local a="$(canonical_arch "$1")" source="$2" karch
  karch="$(linux_karch_for_source "$a" "$source")"
  if [[ -d "$source/arch/x86" && ( "$a" == x86_64 || "$a" == i386 ) ]]; then
    printf '%s\n' arch/x86/boot/bzImage
    return
  fi
  case "$karch" in
    x86_64) printf '%s\n' arch/x86_64/boot/bzImage ;;
    i386) printf '%s\n' arch/i386/boot/bzImage ;;
    *) linux_kernel_image_rel "$a" ;;
  esac
}
linux_defconfig_for_source() {
  local a="$(canonical_arch "$1")" source="$2" karch
  karch="$(linux_karch_for_source "$a" "$source")"
  case "$karch" in
    x86_64|i386) printf '%s\n' defconfig ;;
    *) linux_defconfig "$a" ;;
  esac
}
linux_karch_for_build() {
  local build="$1" a="$(canonical_arch "$2")"
  [[ -f "$build/.klab-karch" ]] && cat "$build/.klab-karch" || linux_karch "$a"
}
linux_kernel_image_rel_for_build() {
  local build="$1" a="$(canonical_arch "$2")" rel
  if [[ -f "$build/.klab-image-rel" ]]; then
    cat "$build/.klab-image-rel"
    return
  fi
  # Builds made before the image-path record was introduced still need to be
  # usable through the stable CLI. Pre-unification x86 trees put their boot
  # image below arch/i386 or arch/x86_64 instead of arch/x86.
  case "$a" in
    i386)
      rel=arch/i386/boot/bzImage
      [[ -f "$build/$rel" ]] && { printf "%s\n" "$rel"; return; }
      ;;
    x86_64)
      rel=arch/x86_64/boot/bzImage
      [[ -f "$build/$rel" ]] && { printf "%s\n" "$rel"; return; }
      ;;
  esac
  linux_kernel_image_rel "$a"
}
linux_console() {
  local a="$(canonical_arch "$1")"
  arch_value_or_fallback "$a" LINUX_CONSOLE "$(case "$a" in x86_64|i386|mips*) echo ttyS0 ;; aarch64|armv7) echo ttyAMA0 ;; esac)"
}
linux_control_tty() {
  local a="$(canonical_arch "$1")"
  arch_value_or_fallback "$a" LINUX_CONTROL_TTY "$(case "$a" in x86_64|i386|mips*) echo /dev/ttyS1 ;; aarch64|armv7) echo /dev/ttyAMA1 ;; esac)"
}
linux_session_console() {
  local arch="$(canonical_arch "$1")" target="${2:-}"
  linux_console "$arch"
}
linux_session_control_tty() {
  local arch="$(canonical_arch "$1")" target="${2:-}"
  linux_control_tty "$arch"
}
qemu_binary_for_arch() {
  [[ -n "$QEMU_OVERRIDE" ]] && { printf '%s\n' "$QEMU_OVERRIDE"; return; }
  local a="$(canonical_arch "$1")" v
  v="$(klab_arch_qemu_binary "$a" 2>/dev/null || true)"; [[ -n "$v" ]] && { printf '%s\n' "$v"; return; }
  case "$a" in x86_64) echo qemu-system-x86_64 ;; i386) echo qemu-system-i386 ;; aarch64) echo qemu-system-aarch64 ;; armv7) echo qemu-system-arm ;; mips) echo qemu-system-mips ;; mipsel) echo qemu-system-mipsel ;; mips64) echo qemu-system-mips64 ;; mips64el) echo qemu-system-mips64el ;; esac
}
qemu_machine_for_arch() {
  local a="$(canonical_arch "$1")" v
  v="$(klab_arch_qemu_machine "$a" 2>/dev/null || true)"; [[ -n "$v" ]] && { printf '%s\n' "$v"; return; }
  case "$a" in x86_64|i386) echo pc ;; aarch64|armv7) echo virt ;; mips*) echo malta ;; esac
}
qemu_kvm_compatible() {
  local guest="$(canonical_arch "$1")" host="$(host_arch)" hosts=""
  [[ -r /dev/kvm && -w /dev/kvm ]] || return 1
  hosts="$(arch_profile_field "$guest" KVM_HOSTS 2>/dev/null || true)"
  if [[ -n "$hosts" ]]; then local h; for h in $hosts; do [[ "$h" == "$host" ]] && return 0; done; return 1; fi
  case "$host:$guest" in x86_64:x86_64|x86_64:i386|aarch64:aarch64|i386:i386) return 0 ;; *) return 1 ;; esac
}
qemu_memory_for_arch() {
  local arch="$(canonical_arch "$1")" v
  v="$(arch_profile_field "$arch" QEMU_MEMORY 2>/dev/null || true)"
  printf '%s\n' "${v:-$MEMORY}"
}
qemu_cpus_for_arch() {
  local arch="$(canonical_arch "$1")" v
  v="$(arch_profile_field "$arch" QEMU_CPUS 2>/dev/null || true)"
  printf '%s\n' "${v:-$CPUS}"
}
qemu_cpu_for_arch() {
  local arch="$(canonical_arch "$1")" cpu=""
  if qemu_kvm_compatible "$arch"; then echo host; return; fi
  cpu="$(arch_profile_field "$arch" QEMU_TCG_CPU 2>/dev/null || true)"
  [[ -n "$cpu" ]] && printf '%s\n' "$cpu" || case "$arch" in x86_64|i386|aarch64) echo max ;; armv7) echo cortex-a15 ;; mips|mipsel) echo 24Kf ;; mips64|mips64el) echo I6400 ;; esac
}
qemu_accel_args() { local arch="$1"; if qemu_kvm_compatible "$arch"; then printf '%s\n' '-enable-kvm' '-cpu' 'host'; else printf '%s\n' '-cpu' "$(qemu_cpu_for_arch "$arch")"; fi; }
qemu_control_mode_for_arch() {
  local arch="$(canonical_arch "$1")" mode
  mode="$(arch_profile_field "$arch" QEMU_CONTROL_MODE 2>/dev/null || true)"
  printf '%s\n' "${mode:-serial}"
}
qemu_control_args() {
  local arch="$(canonical_arch "$1")" sock="$2" mode
  mode="$(qemu_control_mode_for_arch "$arch")"
  case "$mode" in
    serial)
      printf '%s\n' '-serial' "unix:$sock,server=on,wait=off"
      ;;
    virtio-serial)
      printf '%s\n' '-chardev' "socket,id=klabctl,path=$sock,server=on,wait=off" \
        '-device' 'virtio-serial-device' \
        '-device' 'virtserialport,chardev=klabctl,name=org.klab.control'
      ;;
    *) die "unsupported QEMU control mode '$mode' for $arch" ;;
  esac
}
qemu_console_append() { printf 'console=%s\n' "$(linux_console "$1")"; }
qemu_net_device_for_arch() {
  local arch="$(canonical_arch "$1")" dev=""
  dev="$(arch_profile_field "$arch" QEMU_NET_DEVICE 2>/dev/null || true)"
  [[ -n "$dev" ]] && { printf '%s\n' "$dev"; return; }
  case "$arch" in
    x86_64|i386) echo e1000 ;;
    aarch64|armv7) echo virtio-net-device ;;
    mips|mipsel) echo pcnet ;;
    *) return 1 ;;
  esac
}
qemu_net_device_for_target() {
  local arch="$(canonical_arch "$1")" target="${2:-}" modules="${BUNDLE_MODULES_DIR:-}" provider release kernel dir
  if [[ "$arch" == i386 && "$target" == upstream:v2.0.40 ]]; then
    echo ne2k_isa,iobase=0x300,irq=9
    return
  elif [[ "$arch" == i386 && "$target" == upstream:v2.2.26 ]]; then
    echo ne2k_pci
    return
  fi
  if [[ -z "$modules" && "$target" == *:*:* && "$target" != upstream:* ]]; then
    IFS=: read -r provider release kernel <<<"$target"
    dir="$(bundle_existing_dir_for "$provider" "$release" "$kernel" "$arch" 2>/dev/null || true)"
    if [[ -n "$dir" && -f "$dir/bundle.env" ]]; then
      modules="$(sed -n 's/^BUNDLE_MODULES_DIR=//p' "$dir/bundle.env" | head -n1)"
    fi
  fi
  if [[ ( "$arch" == x86_64 || "$arch" == i386 ) && -n "$target" && "$target" != upstream:* && -d "$modules" ]]; then
    if ! find "$modules" -type f -name 'e1000.ko*' -print -quit | grep -q . && find "$modules" -type f -name 'virtio_net.ko*' -print -quit | grep -q .; then
      echo virtio-net-pci
      return
    fi
  fi
  qemu_net_device_for_arch "$arch"
}
qemu_network_args() {
  qemu_network_link_args "$1" "$2" "$3" klabnet0 klabnic0 "" 0
}
qemu_network_link_args() {
  local arch="$(canonical_arch "$1")" bus="$2" mac="$3" netid="$4" devid="$5" capture="${6:-}" delay_us="${7:-0}" target="${8:-}" dev
  [[ "$bus" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]+$ ]] || die "invalid QEMU multicast bus '$bus'"
  [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || die "invalid guest MAC address '$mac'"
  [[ "$netid" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid QEMU netdev id '$netid'"
  [[ "$devid" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid QEMU device id '$devid'"
  [[ "$delay_us" =~ ^[0-9]+$ ]] || die "invalid QEMU network delay '$delay_us'"
  dev="$(qemu_net_device_for_target "$arch" "$target")" || die "no QEMU network device profile for $arch"
  printf '%s\n' '-netdev' "socket,id=$netid,mcast=$bus" '-device' "$dev,netdev=$netid,mac=$mac,id=$devid"
  if [[ -n "$capture" && "$capture" != - ]]; then
    mkdir -p "$(dirname "$capture")"
    printf '%s\n' '-object' "filter-dump,id=${netid}-dump,netdev=$netid,file=$capture"
  fi
  if (( delay_us > 0 )); then
    printf '%s\n' '-object' "filter-buffer,id=${netid}-delay,netdev=$netid,queue=tx,interval=$delay_us"
  fi
}
guest_netmask_for_prefix() {
  case "$1" in
    8) echo 255.0.0.0 ;;
    16) echo 255.255.0.0 ;;
    24) echo 255.255.255.0 ;;
    *) return 1 ;;
  esac
}
configure_guest_network() {
  local sock="$1" cidr="$2" iface="${3:-eth0}" mac="${4:-}" ip prefix mask network cmd resolved="" legacy_config=0 a b c d
  [[ "$cidr" == */* ]] || die "guest network address must be CIDR, got '$cidr'"
  ip="${cidr%/*}"; prefix="${cidr#*/}"
  [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "invalid guest network address '$cidr'"
  mask="$(guest_netmask_for_prefix "$prefix")" || die "KLab guest network currently supports /8, /16, or /24; got /$prefix"
  IFS=. read -r a b c d <<< "$ip"
  case "$prefix" in 8) network="$a.0.0.0" ;; 16) network="$a.$b.0.0" ;; 24) network="$a.$b.$c.0" ;; esac
  if [[ -n "$mac" ]]; then
    [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || die "invalid guest MAC '$mac'"
    # Keep each serial RPC below old ash/read line limits. Resolving the MAC in
    # its own request also avoids nested quoting in the configuration command.
    resolved="$(session_rpc_exec "$sock" "[ ! -r /sys/class/net/'$iface'/address ] && { echo '$iface'; exit 0; }; for d in /sys/class/net/*; do grep -qi '^${mac,,}$' \$d/address 2>/dev/null && { echo \${d##*/}; exit 0; }; done; exit 44")" || return $?
    iface="${resolved##*$'\n'}"
    [[ "$iface" =~ ^[A-Za-z0-9._-]+$ ]] || return 44
    session_rpc_exec "$sock" "[ -r /sys/class/net/'$iface'/address ]" >/dev/null 2>&1 || legacy_config=1
  fi
  if session_rpc_exec "$sock" '[ -x /bin/ifconfig ] || [ -x /sbin/ifconfig ]' >/dev/null 2>&1; then
    if ! session_rpc_exec "$sock" "ifconfig '$iface' '$ip' netmask '$mask' up"; then
      session_rpc_exec "$sock" "ifconfig '$iface' '$ip' && ifconfig '$iface' netmask '$mask' && ifconfig '$iface' up" || return $?
      legacy_config=1
    fi
  else
    session_rpc_exec "$sock" "ip link set '$iface' up; ip addr flush dev '$iface' 2>/dev/null || true; ip addr add '$cidr' dev '$iface'" || return $?
  fi
  if (( legacy_config )); then
    session_rpc_exec "$sock" "route add -net '$network' netmask '$mask' dev '$iface'" || return $?
    printf 'KLAB_LEGACY_NET_CONFIG=%s\nKLAB_NET_IFACE=%s\n' "$ip" "$iface"
    return 0
  fi
  if session_rpc_exec "$sock" "ifconfig '$iface' 2>/dev/null | grep -q 'inet addr:$ip'" >/dev/null 2>&1; then
    session_rpc_exec "$sock" "ifconfig '$iface'; echo KLAB_NET_IFACE=$iface"
  elif session_rpc_exec "$sock" "ifconfig '$iface' 2>/dev/null | grep -q 'inet $ip '" >/dev/null 2>&1; then
    session_rpc_exec "$sock" "ifconfig '$iface'; echo KLAB_NET_IFACE=$iface"
  elif session_rpc_exec "$sock" "ip -4 addr show dev '$iface' 2>/dev/null | grep -q 'inet $ip/'" >/dev/null 2>&1; then
    session_rpc_exec "$sock" "ip -4 addr show dev '$iface'; echo KLAB_NET_IFACE=$iface"
  elif session_rpc_exec "$sock" "grep -q '^[ ]*$iface:' /proc/net/dev 2>/dev/null" >/dev/null 2>&1; then
    printf 'KLAB_LEGACY_NET_CONFIG=%s\nKLAB_NET_IFACE=%s\n' "$ip" "$iface"
  else
    return 45
  fi
}

configure_guest_route() {
  local sock="$1" dest="$2" via="$3" cmd
  cmd="if command -v ip >/dev/null 2>&1; then ip route replace '$dest' via '$via'; else route add -net '${dest%/*}' netmask '$(guest_netmask_for_prefix "${dest#*/}")' gw '$via'; fi"
  session_rpc_exec "$sock" "$cmd"
}

qmp_execute_json() {
  local socket="$1" command="$2" arguments="${3-}"
  [[ -n "$arguments" ]] || arguments='{}'
  [[ -S "$socket" ]] || return 1
  python3 - "$socket" "$command" "$arguments" <<'PYQMPGEN'
import json,socket,sys,time
path,command,args_json=sys.argv[1:]
args=json.loads(args_json)
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); s.settimeout(10)
end=time.time()+10
while True:
    try:s.connect(path);break
    except OSError:
        if time.time()>=end:raise
        time.sleep(.05)
f=s.makefile('rwb',buffering=0)
def recv():
    while True:
        line=f.readline()
        if not line: raise RuntimeError('QMP channel closed')
        obj=json.loads(line)
        if 'event' not in obj:return obj
recv(); f.write(b'{"execute":"qmp_capabilities"}\n'); r=recv()
if 'error' in r: raise RuntimeError(r['error'])
req={'execute':command}
if args:req['arguments']=args
f.write((json.dumps(req,separators=(',',':'))+'\n').encode()); r=recv()
if 'error' in r: raise RuntimeError(r['error'])
print(json.dumps(r.get('return')))
PYQMPGEN
}
qmp_set_link() {
  local socket="$1" device="$2" up="$3" b=false
  [[ "$up" == 1 || "$up" == true || "$up" == on ]] && b=true
  qmp_execute_json "$socket" set_link "{\"name\":\"$device\",\"up\":$b}"
}

freebsd_arch_name() {
  local a="$(canonical_arch "$1")" v=""
  v="$(arch_profile_field "$a" FREEBSD_ARCH 2>/dev/null || true)"
  [[ -n "$v" ]] && printf '%s\n' "$v" || case "$a" in x86_64) echo amd64 ;; aarch64) echo aarch64 ;; i386) echo i386 ;; armv7) echo armv7 ;; esac
}

effective_target_for_arch() {
  local target="$1" arch="$(canonical_arch "$2")"
  if [[ "$target" == freebsd:* ]]; then
    local a b c extra ca
    IFS=: read -r a b c extra <<<"$target"
    [[ -z "$extra" ]] || die "invalid FreeBSD target '$target'"
    if [[ -z "$c" ]]; then printf 'freebsd:%s:%s\n' "$b" "$arch"; else ca="$(canonical_arch "$c")"; [[ "$ca" == "$arch" ]] || die "FreeBSD target embeds architecture $ca but active architecture is $arch; pass --arch $ca"; printf 'freebsd:%s:%s\n' "$b" "$ca"; fi
  else printf '%s\n' "$target"; fi
}

find_aarch64_uefi() {
  local p
  [[ -n "${KLAB_AARCH64_UEFI:-}" ]] && { [[ -f "$KLAB_AARCH64_UEFI" ]] || die "KLAB_AARCH64_UEFI does not exist: $KLAB_AARCH64_UEFI"; printf '%s\n' "$KLAB_AARCH64_UEFI"; return; }
  for p in /usr/share/qemu-efi-aarch64/QEMU_EFI.fd /usr/share/AAVMF/AAVMF_CODE.fd /usr/share/edk2/aarch64/QEMU_EFI.fd /usr/share/edk2/aarch64/QEMU_EFI-silent-pflash.raw; do [[ -f "$p" ]] && { printf '%s\n' "$p"; return; }; done
  return 1
}

ARCH="$(canonical_arch "$ARCH_REQUESTED")"

validate_crashdump_format() {
  case "$CRASHDUMP_FORMAT" in
    elf|kdump-zlib|kdump-lzo|kdump-snappy|kdump-raw-zlib|kdump-raw-lzo|kdump-raw-snappy) ;;
    *) die "unsupported KLAB_CRASHDUMP_FORMAT '$CRASHDUMP_FORMAT'" ;;
  esac
}

usage() {
  cat <<'USAGE'
Kernel Lab v16

Stable workflow
---------------
Connected staging machine:
  kernel-lab.sh init --staging
  kernel-lab.sh prepare <target> [--arch ARCH] [--profile PROFILE] [--userspace SPEC] [--with-sdk] [-o FILE.klab] [--distro-toolchain|--toolchain DIR|--no-toolchain]

Isolated test machine:
  kernel-lab.sh init --offline
  kernel-lab.sh import <FILE.klab>
  kernel-lab.sh targets
  kernel-lab.sh smoke <target> [--arch ARCH] [--profile PROFILE] [--userspace SPEC]
  kernel-lab.sh test <target> --module DIR --script FILE [--arch ARCH] [--profile PROFILE] [--userspace SPEC] [--crashdump] [--panic-on-warn]
  kernel-lab.sh test-set --module DIR --script FILE [--profile PROFILE] [--userspace SPEC] [--workers N] [--jobs-per-worker N] [--crashdump] [--panic-on-warn] <target>...
  kernel-lab.sh build-module <target> --module DIR [--arch ARCH] [--profile PROFILE] [-o DIR]
  kernel-lab.sh build-user <target> --source FILE [-o FILE] [--arch ARCH] [--profile PROFILE] [--userspace buildroot:PROFILE] [-- EXTRA_CC_ARGS...]
  kernel-lab.sh arch-smoke <upstream:VERSION> [--arch ARCH] [--profile PROFILE] [--userspace buildroot:PROFILE] [--artifact-dir DIR] [--keep-session] [--dry-run]
  kernel-lab.sh scenario-run SCENARIO.json [--report-dir DIR] [--keep-session] [--dry-run]
  kernel-lab.sh multiguest-run SCENARIO.json [--report-dir DIR] [--keep-sessions] [--dry-run]
  kernel-lab.sh boot <target> [--arch ARCH] [--profile PROFILE] [--userspace SPEC] [--name SESSION] [--ssh-auth key|password|none] [--ssh-key PRIVATE_KEY] [--ssh-password PASSWORD] [--ssh-bind ADDRESS] [--ssh-port PORT] [--net-bus MCAST:PORT --net-ip CIDR --net-mac MAC] [--crashdump] [--panic-on-warn]
  kernel-lab.sh ssh <SESSION> [-- SSH_OPTIONS...]
  kernel-lab.sh push <SESSION> <LOCAL> [REMOTE]
  kernel-lab.sh exec <SESSION> <COMMAND>
  kernel-lab.sh link <SESSION> <DEVICE-ID> <up|down>
  kernel-lab.sh load-module <SESSION> <MODULE.ko> [module-args...]
  kernel-lab.sh unload-module <SESSION> <MODULE-NAME>
  kernel-lab.sh list-modules <SESSION>
  kernel-lab.sh insmod <SESSION> <MODULE.ko> [module-args...]   # Linux alias
  kernel-lab.sh stop <SESSION>
  kernel-lab.sh crashes
  kernel-lab.sh crash-info <CRASH-ID|SESSION>

Examples:
  ./kernel-lab.sh prepare upstream:v6.6 --arch x86_64 -o linux-6.6-x86_64.klab
  ./kernel-lab.sh prepare upstream:v6.6 --arch aarch64 -o linux-6.6-aarch64.klab
  ./kernel-lab.sh prepare upstream:v6.6 --arch aarch64 --userspace buildroot:minimal --with-sdk -o linux-6.6-aarch64-br.klab
  ./kernel-lab.sh prepare upstream:v6.6 --arch aarch64 --userspace buildroot:network --with-sdk -o linux-6.6-aarch64-net.klab
  ./kernel-lab.sh prepare ubuntu:22.04:5.15.0-191-generic -o ubuntu-5.15.klab

  ./kernel-lab.sh import linux-6.6.klab
  ./kernel-lab.sh import ubuntu-5.15.klab
  ./kernel-lab.sh targets

  ./kernel-lab.sh smoke upstream:v6.6
  ./kernel-lab.sh test upstream:v6.6 --module ./driver --script ./tests/smoke.sh
  ./kernel-lab.sh test ubuntu:22.04:5.15.0-191-generic --module ./driver --script ./tests/smoke.sh
  ./kernel-lab.sh test-set --module ./driver --script ./tests/smoke.sh \
      upstream:v6.6 ubuntu:22.04:5.15.0-191-generic

  ./kernel-lab.sh build-module upstream:v6.6 --module ./driver -o ./out/6.6
  ./kernel-lab.sh build-user upstream:v6.6 --userspace buildroot:minimal --source ./tests/client.c -o ./out/client
  ./kernel-lab.sh boot upstream:v6.6 --name k66 --crashdump
  ./kernel-lab.sh push k66 ./fixtures/input.bin /tmp/input.bin
  ./kernel-lab.sh insmod k66 ./out/6.6/mydriver.ko debug=1
  ./kernel-lab.sh exec k66 'dmesg | tail -50'
  ./kernel-lab.sh stop k66

Stable management commands:
  kernel-lab.sh mode [staging|offline]
  kernel-lab.sh status
  kernel-lab.sh doctor
  kernel-lab.sh architectures
  kernel-lab.sh userspaces
  kernel-lab.sh buildroot-cache [status|check [--arch ARCH --profile PROFILE|--all]]
  kernel-lab.sh arch-plan TARGET_ARCH [--build ARCH] [--kernel VERSION] [--json]
  kernel-lab.sh register-linux NAME --release REL --kernel IMAGE --build-dir DIR [--source-dir DIR] [--arch ARCH]
  kernel-lab.sh cross env  --arch ARCH [--profile minimal|network]
  kernel-lab.sh cross exec --arch ARCH [--profile minimal|network] -- COMMAND...
  kernel-lab.sh cross cc   --arch ARCH [--profile minimal|network] --source FILE [-o FILE] [-- FLAGS...]
  kernel-lab.sh targets
  kernel-lab.sh info <target> [--profile PROFILE]
  kernel-lab.sh verify  <FILE.klab>
  kernel-lab.sh inspect <FILE.klab>
  kernel-lab.sh sessions
  kernel-lab.sh capabilities <target>

Target IDs:
  upstream:v6.6
  upstream:mainline
  ubuntu:22.04:5.15.0-191-generic
  debian:bookworm:6.1.0-40-amd64
  fedora:43:6.17.1-300.fc43.x86_64
  centos:stream9:5.14.0-...el9.x86_64
  rhel:9:5.14.0-...el9.x86_64
  freebsd:15.1-RELEASE:x86_64
  freebsd:15.1-RELEASE:aarch64
  custom:vendor-name:kernel-release

Installed architecture profiles:
  stable upstream Linux: x86_64, i386, aarch64, armv7
  experimental upstream: mips, mipsel, mips64, mips64el (explicit opt-in)
  FreeBSD:             x86_64 + aarch64 automated; 32-bit targets are release/provider gated
  distro Linux:        provider-declared target arches; cross-staging is a separate capability

Profiles apply only to upstream kernels:
  normal (default), debug, kasan, kcsan, lockdep

Linux guest userspace:
  busybox-static      explicit minimal/legacy path; requires KLab RPC applets
  buildroot:minimal   reproducible Buildroot LTS rootfs (modern prepare default)
  buildroot:network   minimal + ip/tc, ethtool, ping/tracepath, iperf3, tcpdump
  buildroot:ssh       network profile + Dropbear for opt-in interactive sessions
  auto                test/boot default; honors the userspace bound into imported .klab

`targets` is the source of truth for what this lab can test without fetching.
`test` never implicitly downloads a target. In offline mode all network-capable
provider commands are rejected.

`boot` starts a persistent QEMU guest with a private serial control channel. Add
`--ssh-auth key|password|none [--ssh-bind 127.0.0.1|0.0.0.0] [--ssh-port PORT]`
to expose Dropbear. Key mode also takes `--ssh-key`; password mode takes
`--ssh-password` or `KLAB_SSH_PASSWORD`. Connect with `kernel-lab.sh ssh SESSION`. `push`,
`exec`, and `load-module` operate over that channel; no guest networking or SSH is required.
Module operations are backend-neutral: Linux maps them to insmod/rmmod/lsmod and FreeBSD
maps them to kldload/kldunload/kldstat.
Serial panic logs are archived automatically. `--crashdump` additionally asks QEMU to
dump guest RAM to an ELF vmcore after a panic; `--panic-on-warn` makes WARN() fatal.

prepare normally resolves and binds a portable kernel.org GCC toolchain when possible.
For historical distro fidelity, --distro-toolchain captures and binds the distribution's actual GCC/binutils package closure as a content-addressed .klabdistrotoolchain and
executes those native tools only inside the matching captured distro build root.
`toolchain distro-capture provider:release:kernel` captures the artifact independently.
Use --no-toolchain only intentionally; use --toolchain DIR for a specific relocatable tree.

Advanced/development commands (not part of the stable workflow):
  build, module, matrix, matrix-targets, providers, list, fetch, toolchain,
  cache, clean, test-legacy

Extensibility:
  Architecture definitions live in ./architectures/*.conf. Set KLAB_ARCH_PROFILES_DIR
  to test additional profiles without editing the core runner. `register-linux` makes
  arbitrary prepared Linux kernels first-class local/portable targets.

Environment overrides:
  KLAB_ROOT, KLAB_JOBS, KLAB_WORKERS, KLAB_MEMORY, KLAB_CPUS, KLAB_BOOT_TIMEOUT,
  KLAB_QEMU, KLAB_BUSYBOX, KLAB_CONTAINER_RUNTIME, KLAB_ARCH, KLAB_USERSPACE,
  KLAB_BUILDROOT_VERSION, KLAB_BUILDROOT_URL_BASE, KLAB_BUILDROOT_CACHE_ONLY,
  KLAB_CRASHDUMP_FORMAT,
  KLAB_BUNDLE_BIN, KLAB_ALLOW_TOOLCHAIN_OVERRIDE, KLAB_CC.
USAGE
}

need_host_tools() {
  local missing=() x
  for x in git make gcc bc bison flex perl python3 cpio gzip zstd tar sha256sum file; do
    have "$x" || missing+=("$x")
  done
  ((${#missing[@]} == 0)) || die "missing staging tools: ${missing[*]}\nOn Debian/Ubuntu try: sudo apt install git build-essential bc bison flex libssl-dev libelf-dev cpio gzip zstd xz-utils"
}

need_offline_tools() {
  local missing=() x
  for x in make perl python3 cpio gzip zstd tar sha256sum file; do
    have "$x" || missing+=("$x")
  done
  ((${#missing[@]} == 0)) || die "missing offline test tools: ${missing[*]}\nInstall the base test dependencies before isolating this VM. QEMU and guest BusyBox are checked per target architecture."
}

require_qemu_arch() {
  local arch="$1" q
  q="$(qemu_binary_for_arch "$arch")"
  have "$q" || die "QEMU for $arch is missing: $q. Install the matching qemu-system package or set KLAB_QEMU=/path/to/qemu-system-*"
  printf '%s\n' "$q"
}

busybox_deb_arch() {
  local a="$(canonical_arch "$1")" v=""
  v="$(arch_profile_field "$a" DEBIAN_ARCH 2>/dev/null || true)"
  [[ -n "$v" ]] && { echo "$v"; return; }
  case "$a" in x86_64) echo amd64 ;; i386) echo i386 ;; aarch64) echo arm64 ;; armv7) echo armhf ;; *) return 1 ;; esac
}

guest_busybox_path() { printf '%s/busybox/%s/busybox\n' "$GUESTS" "$1"; }

validate_guest_busybox() {
  local arch="$1" bb="$2" desc pattern
  arch="$(canonical_arch "$arch")"
  [[ -x "$bb" ]] || return 1
  desc="$(file "$bb" 2>/dev/null || true)"
  [[ "$desc" == *statically\ linked* ]] || return 1
  pattern="$(arch_profile_field "$arch" BUSYBOX_FILE_MATCH 2>/dev/null || true)"
  if [[ -n "$pattern" ]]; then
    printf '%s\n' "$desc" | grep -Eq "$pattern" || return 1
    [[ "$arch" == armv7 && "$desc" == *aarch64* ]] && return 1
    return 0
  fi
  case "$arch" in
    x86_64) [[ "$desc" == *x86-64* || "$desc" == *x86_64* ]] ;;
    i386) [[ "$desc" == *80386* || "$desc" == *Intel\ 80386* ]] ;;
    aarch64) [[ "$desc" == *aarch64* || "$desc" == *ARM\ aarch64* ]] ;;
    armv7) [[ "$desc" == *ARM* && "$desc" != *aarch64* ]] ;;
    *) return 1 ;;
  esac
}

normalize_userspace_spec() {
  case "${1:-auto}" in
    auto) echo auto ;;
    busybox|busybox-static|minimal-busybox) echo busybox-static ;;
    buildroot|buildroot:minimal) echo buildroot:minimal ;;
    buildroot:network|buildroot-network) echo buildroot:network ;;
    buildroot:ssh|buildroot-ssh) echo buildroot:ssh ;;
    ubuntu-native:[0-9]*.[0-9]*) echo "native:ubuntu:${1#ubuntu-native:}" ;;
    native:ubuntu:*|native:debian:*|native:fedora:*|native:centos:*|native:alpine:*|native:arch:*) echo "$1" ;;
    *) die "unsupported guest userspace '$1' (supported: auto, busybox-static, buildroot:minimal, buildroot:network, buildroot:ssh, native:PROVIDER:RELEASE)" ;;
  esac
}

buildroot_defconfig_for_arch() {
  local a="$(canonical_arch "$1")" v=""
  v="$(arch_profile_field "$a" BUILDROOT_DEFCONFIG 2>/dev/null || true)"
  [[ -n "$v" ]] && { printf '%s\n' "$v"; return; }
  case "$a" in
    x86_64) echo qemu_x86_64_defconfig ;;
    i386) echo qemu_x86_defconfig ;;
    aarch64) echo qemu_aarch64_virt_defconfig ;;
    armv7) echo qemu_arm_vexpress_defconfig ;;
    *) die "architecture '$a' does not define BUILDROOT_DEFCONFIG" ;;
  esac
}

buildroot_guest_dir() {
  local arch="$(canonical_arch "$1")" profile="${2:-minimal}"
  printf '%s/buildroot/%s/%s/%s\n' "$GUESTS" "$BUILDROOT_VERSION" "$profile" "$arch"
}

buildroot_rootfs_path() { printf '%s/rootfs.tar\n' "$(buildroot_guest_dir "$1" "${2:-minimal}")"; }
buildroot_guest_metadata_path() { printf '%s/metadata.env\n' "$(buildroot_guest_dir "$1" "${2:-minimal}")"; }
buildroot_sdk_archive_path() { printf '%s/sdk.tar.gz\n' "$(buildroot_guest_dir "$1" "${2:-minimal}")"; }
buildroot_sdk_dir() { printf '%s/sdk\n' "$(buildroot_guest_dir "$1" "${2:-minimal}")"; }
ubuntu_native_rootfs_path() { printf '%s/ubuntu/%s/%s/rootfs.tar.zst\n' "$GUESTS" "$1" "$(canonical_arch "$2")"; }
ubuntu_native_metadata_path() { printf '%s/ubuntu/%s/%s/metadata.env\n' "$GUESTS" "$1" "$(canonical_arch "$2")"; }
native_rootfs_path() { printf '%s/native/%s/%s/%s/rootfs.tar.zst\n' "$GUESTS" "$1" "$2" "$(canonical_arch "$3")"; }
native_metadata_path() { printf '%s/native/%s/%s/%s/metadata.env\n' "$GUESTS" "$1" "$2" "$(canonical_arch "$3")"; }
ensure_native_rootfs() {
  local provider="$1" release="$2" arch="$(canonical_arch "$3")" rootfs meta expected actual
  case "$provider" in ubuntu|debian|fedora|centos|alpine|arch) ;; *) die "unsupported native userspace provider '$provider'" ;; esac
  rootfs="$(native_rootfs_path "$provider" "$release" "$arch")"; meta="$(native_metadata_path "$provider" "$release" "$arch")"
  [[ -s "$rootfs" && -s "$meta" ]] || die "native rootfs is missing for $provider:$release:$arch; run $SELF_DIR/klab-native-rootfs.sh capture $provider $release $arch"
  expected="$(sed -n 's/^KLAB_ROOTFS_SHA256=//p' "$meta")"; actual="$(sha256sum "$rootfs" | awk '{print $1}')"
  [[ -n "$expected" && "$expected" == "$actual" ]] || die "native rootfs checksum mismatch for $provider:$release:$arch"
  printf '%s\n' "$rootfs"
}
ensure_ubuntu_native_rootfs() {
  local release="$1" arch="$(canonical_arch "$2")" rootfs meta expected actual
  [[ "$release" =~ ^(12|14|16|18|20|22|24)\.04$ ]] || die "Ubuntu native v1 supports LTS releases 12.04 through 24.04"
  [[ "$arch" == x86_64 ]] || die "Ubuntu native v1 rootfs artifacts currently support x86_64"
  rootfs="$(ubuntu_native_rootfs_path "$release" "$arch")"; meta="$(ubuntu_native_metadata_path "$release" "$arch")"
  [[ -s "$rootfs" && -s "$meta" ]] || die "Ubuntu $release native rootfs is missing; run $SELF_DIR/klab-ubuntu-native-rootfs.sh capture $release"
  expected="$(sed -n 's/^KLAB_ROOTFS_SHA256=//p' "$meta")"; actual="$(sha256sum "$rootfs" | awk '{print $1}')"
  [[ -n "$expected" && "$expected" == "$actual" ]] || die "Ubuntu $release native rootfs checksum mismatch"
  printf '%s\n' "$rootfs"
}

buildroot_cache_only_enabled() {
  [[ "$OFFLINE" == 1 || "$BUILDROOT_CACHE_ONLY" == 1 ]]
}

need_buildroot_tools() {
  local network_ok="${1:-1}" missing=() x
  for x in make gcc g++ patch perl python3 tar gzip bzip2 xz cpio unzip rsync file sed awk; do
    have "$x" || missing+=("$x")
  done
  if [[ "$network_ok" == 1 ]] && ! have curl && ! have wget; then missing+=(curl-or-wget); fi
  ((${#missing[@]} == 0)) || die "Buildroot host dependencies are missing: ${missing[*]}"
}

br_config_bool() {
  local config="$1" sym="$2" val="$3"
  sed -i -e "/^${sym}=/d" -e "/^# ${sym} is not set$/d" "$config"
  if [[ "$val" == y ]]; then printf '%s=y\n' "$sym" >> "$config"; else printf '# %s is not set\n' "$sym" >> "$config"; fi
}

br_config_string() {
  local config="$1" sym="$2" val="$3" escaped
  sed -i -e "/^${sym}=/d" -e "/^# ${sym} is not set$/d" "$config"
  escaped="${val//\\/\\\\}"; escaped="${escaped//"/\\"}"
  printf '%s="%s"\n' "$sym" "$escaped" >> "$config"
}

ensure_buildroot_source() {
  local cache_only=0
  buildroot_cache_only_enabled && cache_only=1
  need_buildroot_tools "$(( cache_only == 1 ? 0 : 1 ))"
  if [[ -f "$BUILDROOT_SRC/Makefile" ]]; then printf '%s\n' "$BUILDROOT_SRC"; return 0; fi
  local archive="$BUILDROOT_HOME/downloads/buildroot-$BUILDROOT_VERSION.tar.xz" tmp="$BUILDROOT_SRC.tmp.$$"
  mkdir -p "$BUILDROOT_HOME/downloads" "$BUILDROOT_HOME/src" "$BUILDROOT_DL"
  if [[ ! -f "$archive" ]]; then
    if (( cache_only == 1 )); then
      die "Buildroot $BUILDROOT_VERSION source archive is not installed locally. Install a Buildroot cache bundle first (expected: $archive)"
    fi
    say "Fetching Buildroot $BUILDROOT_VERSION (pinned LTS userspace builder)"
    download_url "$BUILDROOT_URL_BASE/buildroot-$BUILDROOT_VERSION.tar.xz" "$archive" || die "failed to download Buildroot $BUILDROOT_VERSION"
    # Keep the upstream signature next to the tarball when reachable. Signature
    # verification is intentionally a separate hardening step; the local SHA is
    # recorded below for reproducibility.
    download_url "$BUILDROOT_URL_BASE/buildroot-$BUILDROOT_VERSION.tar.xz.sign" "$archive.sign" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"; mkdir -p "$tmp"
  tar -xJf "$archive" -C "$tmp" || { rm -rf "$tmp"; die "failed to extract Buildroot archive"; }
  local extracted="$tmp/buildroot-$BUILDROOT_VERSION"
  [[ -f "$extracted/Makefile" ]] || { rm -rf "$tmp"; die "Buildroot archive has unexpected layout"; }
  rm -rf "$BUILDROOT_SRC"; mv "$extracted" "$BUILDROOT_SRC"; rm -rf "$tmp"
  sha256sum "$archive" | awk '{print $1}' > "$BUILDROOT_SRC/.klab-source-archive.sha256"
  printf '%s\n' "$BUILDROOT_SRC"
}

ensure_buildroot_busybox_fragment() {
  local arch="$(canonical_arch "${1:-$ARCH}")" fragment="$BUILDROOT_HOME/klab-busybox.fragment"
  mkdir -p "$BUILDROOT_HOME"
  cat > "$fragment" <<'EOF_KLAB_BUSYBOX'
CONFIG_SH_IS_ASH=y
CONFIG_ASH=y
CONFIG_MOUNT=y
CONFIG_UMOUNT=y
CONFIG_DMESG=y
CONFIG_INSMOD=y
CONFIG_RMMOD=y
CONFIG_LSMOD=y
CONFIG_MODPROBE=y
CONFIG_BASE64=y
CONFIG_STTY=y
CONFIG_MKDIR=y
CONFIG_DIRNAME=y
CONFIG_CHMOD=y
CONFIG_RM=y
CONFIG_HEAD=y
CONFIG_TAIL=y
CONFIG_WC=y
CONFIG_CAT=y
CONFIG_GREP=y
CONFIG_SED=y
CONFIG_AWK=y
CONFIG_SLEEP=y
CONFIG_SYNC=y
CONFIG_POWEROFF=y
CONFIG_REBOOT=y
CONFIG_UNAME=y
EOF_KLAB_BUSYBOX
  [[ "$arch" != i386 ]] || printf '%s\n' 'CONFIG_FEATURE_2_4_MODULES=y' >> "$fragment"
  printf '%s\n' "$fragment"
}

apply_buildroot_profile_config() {
  local config="$1" profile="$2" fragment="$3" cache_only="${4:-0}"
  # Kernel Lab owns the kernel and boot process; Buildroot supplies userspace.
  br_config_bool "$config" BR2_LINUX_KERNEL n
  br_config_bool "$config" BR2_TARGET_ROOTFS_EXT2 n
  br_config_bool "$config" BR2_TARGET_ROOTFS_TAR y
  br_config_bool "$config" BR2_PACKAGE_HOST_QEMU n
  br_config_bool "$config" BR2_PACKAGE_HOST_QEMU_SYSTEM_MODE n
  br_config_bool "$config" BR2_INIT_NONE y
  br_config_bool "$config" BR2_INIT_BUSYBOX n
  br_config_bool "$config" BR2_PACKAGE_BUSYBOX y
  br_config_bool "$config" BR2_TOOLCHAIN_BUILDROOT_UCLIBC n
  br_config_bool "$config" BR2_TOOLCHAIN_BUILDROOT_GLIBC n
  br_config_bool "$config" BR2_TOOLCHAIN_BUILDROOT_MUSL y
  br_config_bool "$config" BR2_STATIC_LIBS y
  br_config_bool "$config" BR2_PACKAGE_HOST_ENVIRONMENT_SETUP y
  br_config_string "$config" BR2_GLOBAL_PATCH_DIR ""
  br_config_string "$config" BR2_SYSTEM_DHCP ""
  br_config_string "$config" BR2_ROOTFS_POST_BUILD_SCRIPT ""
  br_config_string "$config" BR2_ROOTFS_POST_IMAGE_SCRIPT ""
  br_config_string "$config" BR2_ROOTFS_POST_SCRIPT_ARGS ""
  br_config_string "$config" BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES "$fragment"

  if [[ "$profile" == network || "$profile" == ssh ]]; then
    br_config_bool "$config" BR2_PACKAGE_IPROUTE2 y
    br_config_bool "$config" BR2_PACKAGE_ETHTOOL y
    br_config_bool "$config" BR2_PACKAGE_IPERF3 y
    br_config_bool "$config" BR2_PACKAGE_TCPDUMP y
    br_config_bool "$config" BR2_PACKAGE_IPUTILS y
    br_config_bool "$config" BR2_PACKAGE_IPUTILS_PING y
    br_config_bool "$config" BR2_PACKAGE_IPUTILS_TRACEPATH y
  fi
  if [[ "$profile" == ssh ]]; then
    br_config_bool "$config" BR2_PACKAGE_DROPBEAR y
    br_config_bool "$config" BR2_PACKAGE_DROPBEAR_CLIENT n
  fi

  # Fail-closed source policy. Buildroot checks BR2_DL_DIR first. If a source is
  # absent, BR2_PRIMARY_SITE_ONLY prevents the package's normal internet site
  # (and backup mirrors) from being tried; the only fallback is this empty local
  # file:// directory, so a missing cache entry becomes an immediate build error.
  if [[ "$cache_only" == 1 ]]; then
    mkdir -p "$BUILDROOT_OFFLINE_SITE"
    br_config_string "$config" BR2_PRIMARY_SITE "file://$BUILDROOT_OFFLINE_SITE"
    br_config_bool "$config" BR2_PRIMARY_SITE_ONLY y
  else
    br_config_string "$config" BR2_PRIMARY_SITE ""
    br_config_bool "$config" BR2_PRIMARY_SITE_ONLY n
  fi
}

install_busybox_linux24_patch() {
  local src="$1" patch="$SELF_DIR/legacy/patches/busybox-1.37-linux24-musl-module-syscalls.patch"
  [[ -f "$patch" ]] || die "Linux 2.4 BusyBox compatibility patch is missing: $patch"
  mkdir -p "$src/package/busybox"
  cp "$patch" "$src/package/busybox/0021-linux24-musl-module-syscalls.patch"
}

ensure_buildroot_profile() {
  local arch="$(canonical_arch "$1")" profile="${2:-minimal}" dest meta out src defcfg fragment config
  case "$profile" in minimal|network|ssh) ;; *) die "unknown Buildroot userspace profile '$profile'" ;; esac
  dest="$(buildroot_rootfs_path "$arch" "$profile")"; meta="$(buildroot_guest_metadata_path "$arch" "$profile")"
  if [[ -f "$dest" && -f "$meta" ]]; then printf '%s\n' "$dest"; return 0; fi
  src="$(ensure_buildroot_source)" || die "could not prepare local Buildroot source"
  install_busybox_linux24_patch "$src"
  fragment="$(ensure_buildroot_busybox_fragment "$arch")" || die "could not prepare Kernel Lab BusyBox fragment"
  defcfg="$(buildroot_defconfig_for_arch "$arch")"; out="$BUILDROOT_OUT/$BUILDROOT_VERSION/$profile/$arch"; config="$out/.config"
  mkdir -p "$out" "$BUILDROOT_DL" "$(dirname "$dest")"
  say "Configuring Buildroot $BUILDROOT_VERSION/$profile for $arch from $defcfg"
  make -s -C "$src" O="$out" BR2_DL_DIR="$BUILDROOT_DL" "$defcfg" || die "Buildroot defconfig failed for $arch"
  local cache_only=0
  buildroot_cache_only_enabled && cache_only=1
  apply_buildroot_profile_config "$config" "$profile" "$fragment" "$cache_only"
  make -s -C "$src" O="$out" BR2_DL_DIR="$BUILDROOT_DL" olddefconfig || die "Buildroot olddefconfig failed for $arch/$profile"
  if (( cache_only == 1 )); then
    say "Building Buildroot $profile userspace for $arch (strict local source cache)"
  else
    say "Building Buildroot $profile userspace for $arch"
  fi
  # GCC 15 defaults to C23, where bool is a keyword and gnulib releases
  # carried by otherwise supported host packages can omit <stdbool.h>. Keep
  # Buildroot host utilities on the long-supported GNU17 language boundary;
  # target compiler flags and guest ABI are unchanged.
  make -C "$src" O="$out" BR2_DL_DIR="$BUILDROOT_DL" HOST_CFLAGS="-O2 -std=gnu17" HOST_CXXFLAGS="-O2 -std=gnu++17" -j"$JOBS" || die "Buildroot userspace build failed for $arch/$profile"
  [[ -f "$out/images/rootfs.tar" ]] || die "Buildroot did not produce $out/images/rootfs.tar"
  cp "$out/images/rootfs.tar" "$dest"
  cp "$config" "$(dirname "$dest")/buildroot.config"
  cp "$fragment" "$(dirname "$dest")/busybox.fragment"
  local root_sha config_sha source_sha=''
  root_sha="$(sha256sum "$dest" | awk '{print $1}')"; config_sha="$(sha256sum "$config" | awk '{print $1}')"
  [[ -f "$src/.klab-source-archive.sha256" ]] && source_sha="$(cat "$src/.klab-source-archive.sha256")"
  cat > "$meta" <<EOF_BR_META
KLAB_GUEST_USERSPACE=buildroot:$profile
KLAB_GUEST_ARCH=$arch
KLAB_BUILDROOT_VERSION=$BUILDROOT_VERSION
KLAB_BUILDROOT_PROFILE=$profile
KLAB_BUILDROOT_DEFCONFIG=$defcfg
KLAB_BUILDROOT_ROOTFS_SHA256=$root_sha
KLAB_BUILDROOT_CONFIG_SHA256=$config_sha
KLAB_BUILDROOT_SOURCE_SHA256=$source_sha
EOF_BR_META
  printf '%s\n' "$dest"
}

# Backward-compatible helper name retained for older internal callers.
ensure_buildroot_minimal() { ensure_buildroot_profile "$1" "${2:-minimal}"; }

native_dropbear_path() {
  local arch="$(canonical_arch "$1")"
  printf '%s/dropbear/%s/%s/dropbearmulti\n' "$GUESTS" "$DROPBEAR_VERSION" "$arch"
}

ensure_native_dropbear() {
  local arch="$(canonical_arch "$1")" out meta archive sdk cc host build actual
  out="$(native_dropbear_path "$arch")"; meta="$(dirname "$out")/metadata.env"
  if [[ -x "$out" && -s "$meta" ]]; then
    actual="$(sha256sum "$out" | awk '{print $1}')"
    [[ "$actual" == "$(sed -n 's/^KLAB_DROPBEAR_BINARY_SHA256=//p' "$meta")" ]] || die "cached Dropbear checksum mismatch for $arch"
    printf '%s\n' "$out"; return 0
  fi
  archive="$SOURCES/dropbear/dropbear-$DROPBEAR_VERSION.tar.bz2"; mkdir -p "$(dirname "$archive")" "$(dirname "$out")"
  if [[ ! -f "$archive" ]]; then
    download_url "https://matt.ucc.asn.au/dropbear/releases/dropbear-$DROPBEAR_VERSION.tar.bz2" "$archive" >/dev/null || die "could not obtain Dropbear $DROPBEAR_VERSION source"
  fi
  actual="$(sha256sum "$archive" | awk '{print $1}')"; [[ "$actual" == "$DROPBEAR_SHA256" ]] || die "Dropbear source checksum mismatch"
  sdk="$(ensure_buildroot_sdk "$arch" minimal)" || die "could not obtain the $arch static SDK for Dropbear"
  cc="$(find "$sdk/bin" -maxdepth 1 -name '*-buildroot-linux-musl-gcc' -print | head -n1)"; [[ -x "$cc" ]] || die "Buildroot SDK lacks a musl compiler for $arch"
  host="$(basename "$cc" -gcc)"; build="$BUILDROOT_HOME/dropbear-build/$DROPBEAR_VERSION/$arch"; rm -rf "$build"; mkdir -p "$build"
  tar -xjf "$archive" -C "$build" --strip-components=1 || die "could not extract Dropbear source"
  printf '%s\n' '#define DEFAULT_PATH "/usr/sbin:/usr/bin:/sbin:/bin"' >> "$build/localoptions.h"
  (cd "$build" && CC="$cc" ./configure --host="$host" --disable-zlib --enable-bundled-libtom --disable-lastlog --disable-wtmp --disable-utmp --disable-utmpx --disable-wtmpx --disable-harden --enable-static >configure.log 2>&1 && make -s -j"$JOBS" MULTI=1 SCPPROGRESS=0 PROGRAMS='dropbear dropbearkey' >make.log 2>&1) || die "static Dropbear build failed for $arch; see $build/configure.log and $build/make.log"
  file "$build/dropbearmulti" | grep -Fq 'statically linked' || die "Dropbear fallback for $arch is not static"
  klab_arch_e2e_file_matches "$arch" "$(file "$build/dropbearmulti")" || die "Dropbear fallback does not match $arch"
  install -m 0755 "$build/dropbearmulti" "$out"; actual="$(sha256sum "$out" | awk '{print $1}')"
  cat > "$meta" <<EOF_DROPBEAR_META
KLAB_DROPBEAR_VERSION=$DROPBEAR_VERSION
KLAB_DROPBEAR_ARCH=$arch
KLAB_DROPBEAR_SOURCE_SHA256=$DROPBEAR_SHA256
KLAB_DROPBEAR_BINARY_SHA256=$actual
KLAB_DROPBEAR_STATIC=1
EOF_DROPBEAR_META
  rm -rf "$build"
  printf '%s\n' "$out"
}

legacy_dropbear_guest_arch() {
  local target="$1" arch="$(canonical_arch "$2")" patch
  case "$target:$arch" in
    upstream:v2.6.*:x86_64|upstream:v2.6.*:i386)
      patch="${target#upstream:v2.6.}"; patch="${patch%%[^0-9]*}"
      [[ "$patch" =~ ^[0-9]+$ && "$patch" -le 34 ]] || return 1
      # x86_64 kernels in this range carry IA32 emulation. The i386 binary
      # avoids modern x86_64 musl TLS/syscall assumptions on the affected early 2.6 kernels.
      printf '%s\n' i386
      ;;
    *) return 1 ;;
  esac
}

ensure_legacy_native_dropbear() {
  local arch="$1"
  ( DROPBEAR_VERSION=2020.81
    DROPBEAR_SHA256=48235d10b37775dbda59341ac0c4b239b82ad6318c31568b985730c788aac53b
    ensure_native_dropbear "$arch" )
}

install_native_ssh_backend() {
  local root="$1" arch="$2" target="${3:-}" fallback fallback_arch=""
  mkdir -p "$root/etc"
  if [[ "${KLAB_NATIVE_SSH_FORCE_DROPBEAR:-0}" != 1 && -x "$root/usr/sbin/sshd" ]]; then
    printf '%s\n' openssh > "$root/etc/klab-ssh-backend"; return 0
  fi
  if [[ -x "$root/usr/sbin/dropbear" && -x "$root/usr/bin/dropbearkey" ]]; then
    printf '%s\n' dropbear-native > "$root/etc/klab-ssh-backend"; return 0
  fi
  if fallback_arch="$(legacy_dropbear_guest_arch "$target" "$arch" 2>/dev/null)"; then
    fallback="$(ensure_legacy_native_dropbear "$fallback_arch")" || return 1
  else
    fallback="$(ensure_native_dropbear "$arch")" || return 1
  fi
  mkdir -p "$root/usr/sbin" "$root/usr/bin"; install -m 0755 "$fallback" "$root/usr/sbin/dropbear"
  ln -sfn ../sbin/dropbear "$root/usr/bin/dropbearkey"
  printf '%s\n' dropbear-fallback > "$root/etc/klab-ssh-backend"
}

ensure_buildroot_sdk() {
  local arch="$(canonical_arch "$1")" profile="${2:-minimal}" sdk archive meta out src found sha
  case "$profile" in minimal|network|ssh) ;; *) die "unknown Buildroot SDK profile '$profile'" ;; esac
  archive="$(buildroot_sdk_archive_path "$arch" "$profile")"; sdk="$(buildroot_sdk_dir "$arch" "$profile")"; meta="$(buildroot_guest_metadata_path "$arch" "$profile")"
  if [[ -d "$sdk" && -x "$sdk/relocate-sdk.sh" && -f "$archive" ]]; then printf '%s\n' "$sdk"; return 0; fi
  if [[ -f "$archive" && ! -d "$sdk" ]]; then
    mkdir -p "$sdk"; tar -xzf "$archive" -C "$sdk" --strip-components=1 || die "failed to extract cached Buildroot SDK"
    [[ -x "$sdk/relocate-sdk.sh" ]] || die "cached Buildroot SDK lacks relocate-sdk.sh"
    (cd "$sdk" && ./relocate-sdk.sh >&2) || die "cached Buildroot SDK relocation failed"
    printf '%s\n' "$sdk"; return 0
  fi
  ensure_buildroot_profile "$arch" "$profile" >/dev/null
  src="$(ensure_buildroot_source)" || die "could not prepare local Buildroot source"
  out="$BUILDROOT_OUT/$BUILDROOT_VERSION/$profile/$arch"
  # An imported rootfs cache may exist without Buildroot's output tree. Rebuild
  # the profile when necessary so make sdk has a complete host/.
  if [[ ! -f "$out/.config" ]]; then
    rm -f "$(buildroot_rootfs_path "$arch" "$profile")" "$meta"
    ensure_buildroot_profile "$arch" "$profile" >/dev/null
  fi
  if buildroot_cache_only_enabled; then
    local sdk_fragment="$(ensure_buildroot_busybox_fragment "$arch")"
    apply_buildroot_profile_config "$out/.config" "$profile" "$sdk_fragment" 1
    make -s -C "$src" O="$out" BR2_DL_DIR="$BUILDROOT_DL" olddefconfig || die "Buildroot offline SDK olddefconfig failed for $arch/$profile"
  fi
  say "Building relocatable Buildroot SDK $BUILDROOT_VERSION/$profile for $arch"
  make -C "$src" O="$out" BR2_DL_DIR="$BUILDROOT_DL" sdk || die "Buildroot SDK generation failed for $arch/$profile"
  found="$(find "$out/images" -maxdepth 1 -type f -name '*_sdk-buildroot.tar.gz' -print | head -n1)"
  [[ -f "$found" ]] || die "Buildroot make sdk did not produce an SDK archive"
  cp "$found" "$archive"
  rm -rf "$sdk"; mkdir -p "$sdk"
  tar -xzf "$archive" -C "$sdk" --strip-components=1 || die "failed to extract Buildroot SDK"
  [[ -x "$sdk/relocate-sdk.sh" ]] || die "Buildroot SDK lacks relocate-sdk.sh"
  (cd "$sdk" && ./relocate-sdk.sh >&2) || die "Buildroot SDK relocation failed"
  sha="$(sha256sum "$archive" | awk '{print $1}')"
  cat >> "$meta" <<EOF_BR_SDK
KLAB_BUILDROOT_SDK_SHA256=$sha
KLAB_BUILDROOT_SDK_ARCHIVE=$archive
KLAB_BUILDROOT_SDK_DIR=$sdk
EOF_BR_SDK
  printf '%s\n' "$sdk"
}

ensure_guest_userspace() {
  local spec arch
  spec="$(normalize_userspace_spec "$1")"; arch="$(canonical_arch "$2")"
  case "$spec" in
    busybox-static) ensure_guest_busybox "$arch" ;;
    buildroot:minimal) ensure_buildroot_profile "$arch" minimal ;;
    buildroot:network) ensure_buildroot_profile "$arch" network ;;
    buildroot:ssh) ensure_buildroot_profile "$arch" ssh ;;
    native:*)
      local _native _provider _release
      IFS=: read -r _native _provider _release <<<"$spec"
      ensure_native_rootfs "$_provider" "$_release" "$arch"
      ;;
    auto) die "internal error: 'auto' userspace must be resolved before acquisition" ;;
  esac
}

populate_guest_root() {
  local root="$1" spec arch rootfs
  spec="$(normalize_userspace_spec "$2")"; arch="$(canonical_arch "$3")"
  mkdir -p "$root"
  case "$spec" in
    busybox-static)
      mkdir -p "$root"/{bin,sbin,proc,sys,dev,tmp,etc}
      local guest_bb x
      if [[ "$ACTIVE_USERSPACE_SPEC" == busybox-static && -n "$ACTIVE_USERSPACE_ARTIFACT" && -x "$ACTIVE_USERSPACE_ARTIFACT" ]]; then
        guest_bb="$ACTIVE_USERSPACE_ARTIFACT"
      else
        guest_bb="$(ensure_guest_busybox "$arch")" || die "could not obtain guest BusyBox for $arch"
      fi
      local legacy_base64="" linux22_overlay="" linux22_modutils="" linux20_modutils=""
      if [[ "$guest_bb" == "$(linux22_guest_busybox_path "$arch")" ]]; then
        linux22_overlay="$(legacy_ssh_rootfs_path)"
        [[ -f "$linux22_overlay" ]] || die "sealed Linux 2.0/2.2 rootfs is missing: $linux22_overlay"
        tar --no-same-owner --exclude='./dev/*' --exclude='dev/*' --exclude='./init' --exclude='init' -xf "$linux22_overlay" -C "$root" || die "could not extract Linux 2.0/2.2 compatibility root"
        linux22_modutils="$(ensure_linux22_modutils)"
        cp -a "$linux22_modutils/sbin/." "$root/sbin/" || die "could not install Linux 2.2 modutils"
        linux20_modutils="$(ensure_linux20_modutils)"
        mkdir -p "$root/sbin/linux20"
        cp -a "$linux20_modutils/sbin/." "$root/sbin/linux20/" || die "could not install Linux 2.0 modutils"
      fi
      if ! "$guest_bb" base64 --help >/dev/null 2>&1; then
        legacy_base64="$(ensure_legacy_base64 "$arch")"
      fi
      cp "$guest_bb" "$root/bin/busybox" || die "failed to install guest BusyBox"
      for x in sh mount umount dmesg insmod rmmod lsmod modprobe ls cat cp mv grep sed awk sleep sync poweroff reboot uname base64 mkdir dirname chmod chown rm stty touch head tail wc ifconfig route ping test expr true false \[ echo printf kill hostname ps netstat; do
        ln -sf busybox "$root/bin/$x"
      done
      if [[ -n "$linux22_modutils" ]]; then
        for x in insmod rmmod lsmod modprobe; do ln -sf "/sbin/$x" "$root/bin/$x"; done
      fi
      [[ -z "$legacy_base64" ]] || install -m 0755 "$legacy_base64" "$root/bin/base64"
      ;;
    native:*)
      local _native _provider _release
      IFS=: read -r _native _provider _release <<<"$spec"
      rootfs="$(ensure_native_rootfs "$_provider" "$_release" "$arch")"
      zstd -dc "$rootfs" | tar --no-same-owner --exclude='./dev/*' --exclude='dev/*' -xf - -C "$root" || die "failed to extract native userspace"
      mkdir -p "$root"/{proc,sys,dev,tmp,etc,bin,sbin}
      [[ -e "$root/bin/sh" || -e "$root/usr/bin/sh" ]] || die "native rootfs lacks /bin/sh"
      ;;
    buildroot:minimal|buildroot:network|buildroot:ssh)
      local brprofile="${spec#buildroot:}"
      if [[ "$ACTIVE_USERSPACE_SPEC" == "$spec" && -n "$ACTIVE_USERSPACE_ARTIFACT" && -f "$ACTIVE_USERSPACE_ARTIFACT" ]]; then
        rootfs="$ACTIVE_USERSPACE_ARTIFACT"
      else
        rootfs="$(ensure_buildroot_profile "$arch" "$brprofile")" || die "could not obtain Buildroot $brprofile userspace for $arch"
      fi
      # Device nodes in the tarball are unnecessary because every KLab guest
      # mounts devtmpfs. Excluding them also keeps extraction unprivileged.
      tar --no-same-owner --exclude='./dev/*' --exclude='dev/*' -xf "$rootfs" -C "$root" || die "failed to extract Buildroot userspace"
      mkdir -p "$root"/{proc,sys,dev,tmp,etc,bin,sbin}
      [[ -e "$root/bin/sh" || -e "$root/usr/bin/sh" ]] || die "Buildroot rootfs lacks /bin/sh"
      ;;
    *) die "cannot populate unknown userspace '$spec'" ;;
  esac
}

write_mode() {
  local mode="$1"
  [[ "$mode" == staging || "$mode" == offline ]] || die "mode must be 'staging' or 'offline'"
  mkdir -p "$LAB_HOME"
  printf '%s\n' "$mode" > "$MODE_FILE"
  if [[ "$mode" == offline ]]; then OFFLINE=1; else OFFLINE=0; fi
}

cmd_mode() {
  if (($# == 0)); then
    if [[ -f "$MODE_FILE" ]]; then cat "$MODE_FILE"; elif [[ "$OFFLINE" == 1 ]]; then echo offline; else echo staging; fi
    return
  fi
  (($# == 1)) || die "usage: $0 mode [staging|offline]"
  write_mode "$1"
  say "Lab mode set to $1"
}

init_lab() {
  local mode=staging
  case "${1:-}" in
    --offline|offline) mode=offline ;;
    --staging|staging|'') mode=staging ;;
    *) die "usage: $0 init [--staging|--offline]" ;;
  esac
  if [[ "$mode" == offline ]]; then need_offline_tools; else need_host_tools; fi
  mkdir -p "$LAB_HOME" "$SOURCES" "$BUILDS" "$INITRAMFS" "$LOGS" "$EXAMPLES" "$KERNELS" "$TOOLCHAINS" "$JOBS_ROOT" "$SESSIONS" "$ARTIFACTS" "$CRASHES" "$EXPORTS" "$GUESTS"
  write_mode "$mode"

  if [[ "$mode" == staging && ! -d "$SRC/.git" ]]; then
    say "Creating on-demand kernel source repository"
    git init -q "$SRC"
    git -C "$SRC" remote add stable "$STABLE_URL"
    git -C "$SRC" remote add mainline "$MAINLINE_URL"
  fi

  mkdir -p "$EXAMPLES/hello"
  if [[ ! -e "$EXAMPLES/hello/hello.c" ]]; then
    cat > "$EXAMPLES/hello/hello.c" <<'EOC'
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
static int __init hello_init(void) { pr_info("kernel_lab_hello: loaded\n"); return 0; }
static void __exit hello_exit(void) { pr_info("kernel_lab_hello: unloaded\n"); }
module_init(hello_init); module_exit(hello_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("kernel-lab smoke-test module");
EOC
    cat > "$EXAMPLES/hello/Makefile" <<'EOM'
obj-m := hello.o
EOM
    cat > "$EXAMPLES/test.sh" <<'EOT'
#!/bin/sh
set -eu
i=0
while ! dmesg | grep -q 'kernel_lab_hello: loaded'; do
  i=$((i+1))
  [ "$i" -lt 5 ] || exit 1
  sleep 1
done
echo "guest test saw hello module"
EOT
    chmod +x "$EXAMPLES/test.sh"
  fi
  if [[ ! -e "$EXAMPLES/user-test.c" ]]; then
    cat > "$EXAMPLES/user-test.c" <<'EOUSER'
#include <stdio.h>
#include <sys/utsname.h>
int main(void) {
    struct utsname u;
    if (uname(&u) != 0) return 1;
    printf("kernel-lab user test: machine=%s pointer_bits=%zu\n", u.machine, sizeof(void *) * 8);
    return 0;
}
EOUSER
  fi

  cat <<EOMSG
Initialized $mode lab: $LAB_HOME

$(if [[ "$mode" == staging ]]; then printf 'Next: %s\n' "  $0 prepare upstream:v6.6"; else printf 'Next: %s\n' "  $0 import /path/to/kernel.klab"; fi)
EOMSG
}

bundle_tool() {
  [[ -f "$BUNDLE_BIN" ]] || die "bundle helper not found: $BUNDLE_BIN"
  KLAB_ARCH="$ARCH" KLAB_GUEST_BUSYBOX_OVERRIDE="${KLAB_GUEST_BUSYBOX_OVERRIDE:-}" bash "$BUNDLE_BIN" "$@"
}

cmd_status() {
  local mode targets=0 sessions=0 crashes=0 running=0 d size workers="${KLAB_WORKERS:-1}"
  mode="$(cmd_mode)"
  [[ -d "$KERNELS" ]] && targets=$((targets + $(find "$KERNELS" -type f -name bundle.env 2>/dev/null | wc -l)))
  [[ -d "$BUILDS" ]] && targets=$((targets + $(find "$BUILDS" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)))
  if [[ -d "$SESSIONS" ]]; then
    for d in "$SESSIONS"/*; do
      [[ -d "$d" ]] || continue; sessions=$((sessions+1))
      if [[ -f "$d/pid" ]] && kill -0 "$(cat "$d/pid" 2>/dev/null)" 2>/dev/null; then running=$((running+1)); fi
    done
  fi
  [[ -d "$CRASHES" ]] && crashes="$(find "$CRASHES" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | awk '{print $1}')"
  size="$(du -sh "$LAB_HOME" 2>/dev/null | awk '{print $1}')"; [[ -n "$size" ]] || size=0
  cat <<EOF_STATUS
Kernel Lab v16
Home:              $LAB_HOME
Mode:              $mode
Disk used:         $size
Cached targets:    $targets
Sessions:          $running running / $sessions recorded
Crash archives:    $crashes
Default arch:      $ARCH
Build jobs:        $JOBS
Test-set workers:  $workers
Buildroot version: $BUILDROOT_VERSION
Arch profiles:     $ARCH_PROFILES_DIR
EOF_STATUS
  if [[ -d "$BUILDROOT_DL" ]]; then printf 'Buildroot dl cache: %s\n' "$(du -sh "$BUILDROOT_DL" 2>/dev/null | awk '{print $1}')"; fi
  printf '\nNext useful commands: targets | sessions | architectures | userspaces | doctor\n'
}

cmd_doctor() {
  local mode a q bb status
  mode="$(cmd_mode)"
  printf 'Kernel Lab home: %s\nMode:            %s\nBundle helper:   %s\n' "$LAB_HOME" "$mode" "$BUNDLE_BIN"
  if [[ "$mode" == offline ]]; then need_offline_tools; else need_host_tools; fi
  [[ -f "$BUNDLE_BIN" ]] || die "bundle helper missing: $BUNDLE_BIN"
  printf '\n%-10s %-30s %-12s\n' ARCH QEMU GUEST_BUSYBOX
  while IFS= read -r a; do
    q="$(qemu_binary_for_arch "$a")"
    bb="$(guest_busybox_path "$a")"
    if have "$q"; then q="$(command -v "$q")"; else q='missing'; fi
    if validate_guest_busybox "$a" "$bb" 2>/dev/null; then status='ready'; else status='missing'; fi
    printf '%-10s %-30s %-12s\n' "$a" "$q" "$status"
  done < <(architecture_ids)
  printf '\nStatus: core dependencies OK. Per-architecture QEMU/BusyBox are required only when that architecture is used.\n'
  printf 'Run %s userspaces to inspect cached BusyBox-static and Buildroot-minimal guest images.\n' "$0"
}

cmd_architectures() {
  local a q qstate accel bbstate fwstate linux freebsd status family bits endian abi e2e
  printf '%-10s %-12s %-8s %-6s %-7s %-10s %-10s %-8s %-20s %-18s %-10s\n' ARCH STATUS FAMILY BITS ENDIAN ABI E2E QEMU LINUX FREEBSD BUSYBOX
  printf '%-10s %-12s %-8s %-6s %-7s %-10s %-10s %-8s %-20s %-18s %-10s\n' '----' '------' '------' '----' '------' '---' '---' '----' '-----' '-------' '-------'
  while IFS= read -r a; do
    q="$(qemu_binary_for_arch "$a")"; if have "$q"; then qstate=ready; else qstate=missing; fi
    if qemu_kvm_compatible "$a"; then accel=KVM; else accel=TCG; fi
    if validate_guest_busybox "$a" "$(guest_busybox_path "$a")" 2>/dev/null; then bbstate=ready; else bbstate=missing; fi
    status="$(klab_arch_status "$a")"; family="$(klab_arch_family "$a" 2>/dev/null || echo -)"; bits="$(klab_arch_bits "$a" 2>/dev/null || echo -)"; endian="$(klab_arch_endian "$a" 2>/dev/null || echo -)"; abi="$(klab_arch_abi "$a" 2>/dev/null || echo -)"; e2e="$(klab_arch_e2e_status "$a" 2>/dev/null || echo disabled)"
    linux='upstream'; freebsd='profile/manual'; fwstate=n/a
    case "$a" in
      x86_64) linux='upstream+distro'; freebsd='automated' ;;
      i386) freebsd='14.x gated' ;;
      aarch64) freebsd='automated'; if find_aarch64_uefi >/dev/null 2>&1; then fwstate=ready; else fwstate=missing; fi ;;
      armv7) freebsd='media/manual' ;;
      mips*) linux='upstream(exp)'; freebsd='n/a' ;;
      *) [[ -n "$(arch_profile_field "$a" FREEBSD_ARCH 2>/dev/null || true)" ]] || freebsd='n/a' ;;
    esac
    [[ "$accel" == KVM ]] && qstate="${qstate}/KVM"
    printf '%-10s %-12s %-8s %-6s %-7s %-10s %-10s %-8s %-20s %-18s %-10s\n' "$a" "$status" "$family" "$bits" "$endian" "$abi" "$e2e" "$qstate" "$linux" "$freebsd" "$bbstate"
  done < <(architecture_ids)
  printf '\nModel: target_arch != build_arch is cross compilation; toolchain_exec_arch=build_arch; toolchain_target_arch=guest_arch=target_arch.\n'
  printf 'Experimental profiles require KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 for build/boot operations.\n'
}

cmd_arch_plan() {
  local target='' build="$(host_arch)" kernel='' json=0 plan status min
  (($# >= 1)) || die "usage: $0 arch-plan TARGET_ARCH [--build ARCH] [--kernel VERSION] [--json]"
  target="$(canonical_arch "$1")"; shift
  while (($#)); do
    case "$1" in
      --build) [[ $# -ge 2 ]] || die "--build needs an architecture"; build="$(canonical_arch "$2")"; shift 2 ;;
      --kernel) [[ $# -ge 2 ]] || die "--kernel needs a version/release"; kernel="$2"; shift 2 ;;
      --json) json=1; shift ;;
      *) die "unknown arch-plan option '$1'" ;;
    esac
  done
  plan="$(klab_arch_plan_json "$target" "$build")" || die "could not construct architecture plan"
  if [[ -n "$kernel" ]] && ! klab_arch_kernel_supported "$target" "$kernel"; then
    min="$(arch_profile_field "$target" KERNEL_MIN_VERSION 2>/dev/null || true)"
    die "kernel $kernel is outside the supported version range for $target${min:+ (minimum $min)}"
  fi
  if (( json == 1 )); then printf '%s\n' "$plan"; return; fi
  python3 - "$plan" "$kernel" <<'PY_ARCH_PLAN'
import json,sys
m=json.loads(sys.argv[1]); kernel=sys.argv[2]
p=m['profile']; e=m['execution']; pkg=m['package_arch']
print(f"Target arch:          {m['target_arch']}")
print(f"Build arch:           {m['build_arch']}")
print(f"Toolchain exec arch:  {m['toolchain_exec_arch']}")
print(f"Toolchain target:     {m['toolchain_target_arch']}")
print(f"Guest arch:           {m['guest_arch']}")
print(f"Cross compilation:    {'yes' if m['cross_compile'] else 'no'}")
print(f"Profile:              {p.get('status')} / {p.get('family')} / {p.get('bits')}-bit / {p.get('endian')} / {p.get('abi')}")
print(f"Linux ARCH:           {p.get('kernel_arch')}")
print(f"Kernel minimum:       {p.get('kernel_min_version') or '-'}")
print(f"QEMU:                 {e.get('qemu_binary') or '-'} / {e.get('qemu_machine') or '-'}")
print(f"E2E status:           {e.get('e2e_status') or 'disabled'}")
print(f"Guest control:        {e.get('control_mode') or '-'} / {e.get('control_device') or '-'}")
print(f"Package arches:       deb={pkg.get('debian') or '-'} rpm={pkg.get('rpm') or '-'} apk={pkg.get('apk') or '-'}")
if kernel: print(f"Requested kernel:     {kernel} (model-compatible)")
PY_ARCH_PLAN
}

buildroot_cache_status() {
  local archive="$BUILDROOT_HOME/downloads/buildroot-$BUILDROOT_VERSION.tar.xz" mode
  if buildroot_cache_only_enabled; then mode='strict-local-only'; else mode='network-allowed-on-staging'; fi
  printf 'Buildroot version:     %s\n' "$BUILDROOT_VERSION"
  printf 'Policy:                %s\n' "$mode"
  printf 'Source archive:        %s\n' "$([[ -f "$archive" ]] && echo ready || echo missing)"
  printf 'Extracted source:      %s\n' "$([[ -f "$BUILDROOT_SRC/Makefile" ]] && echo ready || echo missing)"
  if [[ -d "$BUILDROOT_DL" ]]; then
    printf 'Download cache:        %s (%s files)\n' "$(du -sh "$BUILDROOT_DL" 2>/dev/null | awk '{print $1}')" "$(find "$BUILDROOT_DL" -type f | wc -l | awk '{print $1}')"
  else
    printf 'Download cache:        missing\n'
  fi
  printf 'Offline primary site:  %s\n' "$BUILDROOT_OFFLINE_SITE"
  printf 'Lab role:              %s\n' "$(cmd_mode)"
}

buildroot_cache_check_one() {
  local arch="$(canonical_arch "$1")" profile="$2" src fragment defcfg out config
  case "$profile" in minimal|network|ssh) ;; *) die "unknown Buildroot userspace profile '$profile'" ;; esac
  src="$(ensure_buildroot_source)" || return 1
  fragment="$(ensure_buildroot_busybox_fragment "$arch")" || return 1
  defcfg="$(buildroot_defconfig_for_arch "$arch")"
  out="$BUILDROOT_HOME/cache-check/$BUILDROOT_VERSION/$profile/$arch"
  config="$out/.config"
  rm -rf "$out"; mkdir -p "$out" "$BUILDROOT_DL" "$BUILDROOT_OFFLINE_SITE"
  say "Checking Buildroot source cache for $profile/$arch (no network fallback)"
  make -s -C "$src" O="$out" BR2_DL_DIR="$BUILDROOT_DL" "$defcfg" || return 1
  apply_buildroot_profile_config "$config" "$profile" "$fragment" 1
  make -s -C "$src" O="$out" BR2_DL_DIR="$BUILDROOT_DL" olddefconfig || return 1
  if make -C "$src" O="$out" BR2_DL_DIR="$BUILDROOT_DL" source; then
    printf 'READY  %-10s %s\n' "$arch" "$profile"
    return 0
  fi
  printf 'MISSING %-10s %s\n' "$arch" "$profile" >&2
  return 1
}

cmd_buildroot_cache() {
  local sub="${1:-status}"
  [[ $# -gt 0 ]] && shift || true
  case "$sub" in
    status)
      (($# == 0)) || die "usage: $0 buildroot-cache status"
      buildroot_cache_status
      ;;
    check)
      local arch="$ARCH" profile=minimal all=0 failures=0 a p
      while (($#)); do
        case "$1" in
          --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; arch="$(canonical_arch "$2")"; shift 2 ;;
          --profile) [[ $# -ge 2 ]] || die "--profile needs a value"; profile="$2"; shift 2 ;;
          --all) all=1; shift ;;
          *) die "unknown buildroot-cache check option '$1'" ;;
        esac
      done
      if (( all == 1 )); then
        while IFS= read -r a; do
          for p in minimal network; do
            buildroot_cache_check_one "$a" "$p" || failures=$((failures + 1))
          done
        done < <(architecture_ids)
      else
        buildroot_cache_check_one "$arch" "$profile" || failures=1
      fi
      (( failures == 0 )) || die "$failures Buildroot cache profile(s) are incomplete"
      ;;
    *) die "usage: $0 buildroot-cache [status|check [--arch ARCH --profile PROFILE|--all]]" ;;
  esac
}

cmd_userspaces() {
  local a bb min net sshroot bbstate minstate netstate sshstate minsdk netsdk sshsdk
  printf 'Buildroot pinned version: %s\n\n' "$BUILDROOT_VERSION"
  printf '%-10s %-16s %-18s %-18s %-18s %-12s %-12s %-12s\n' ARCH BUSYBOX BUILDROOT_MINIMAL BUILDROOT_NETWORK BUILDROOT_SSH MIN_SDK NET_SDK SSH_SDK
  printf '%-10s %-16s %-18s %-18s %-18s %-12s %-12s %-12s\n' '----' '-------' '-----------------' '-----------------' '-------------' '-------' '-------' '-------'
  while IFS= read -r a; do
    bb="$(guest_busybox_path "$a")"; min="$(buildroot_rootfs_path "$a" minimal)"; net="$(buildroot_rootfs_path "$a" network)"; sshroot="$(buildroot_rootfs_path "$a" ssh)"
    validate_guest_busybox "$a" "$bb" 2>/dev/null && bbstate=ready || bbstate=missing
    [[ -f "$min" && -f "$(buildroot_guest_metadata_path "$a" minimal)" ]] && minstate=ready || minstate=missing
    [[ -f "$net" && -f "$(buildroot_guest_metadata_path "$a" network)" ]] && netstate=ready || netstate=missing
    [[ -f "$sshroot" && -f "$(buildroot_guest_metadata_path "$a" ssh)" ]] && sshstate=ready || sshstate=missing
    [[ -d "$(buildroot_sdk_dir "$a" minimal)" ]] && minsdk=ready || minsdk=missing
    [[ -d "$(buildroot_sdk_dir "$a" network)" ]] && netsdk=ready || netsdk=missing
    [[ -d "$(buildroot_sdk_dir "$a" ssh)" ]] && sshsdk=ready || sshsdk=missing
    printf '%-10s %-16s %-18s %-18s %-18s %-12s %-12s %-12s\n' "$a" "$bbstate" "$minstate" "$netstate" "$sshstate" "$minsdk" "$netsdk" "$sshsdk"
  done < <(architecture_ids)
  printf '\nBuildroot userspace/SDK artifacts are generated on staging and may be carried inside .klab bundles for offline use.\n'
}

cmd_prepare() {
  [[ "$OFFLINE" != 1 ]] || die "offline lab: prepare is disabled; prepare bundles on the staging machine"
  (($# >= 1)) || die "usage: $0 prepare <target> [--arch ARCH] [--profile PROFILE] [--userspace SPEC] [--with-sdk] [--artifact-dir DIR] [-o FILE.klab] [--no-toolchain|--toolchain DIR|--distro-toolchain]"
  local requested_target="$1" target; shift
  local profile=normal output="" artifact_dir="" tc_mode=auto tc_dir="" arch="$ARCH" userspace="${KLAB_PREPARE_USERSPACE:-${KLAB_USERSPACE:-auto}}" with_sdk=0
  while (($#)); do
    case "$1" in
      --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; arch="$(canonical_arch "$2")"; shift 2 ;;
      --profile) [[ $# -ge 2 ]] || die "--profile needs a value"; profile="$2"; shift 2 ;;
      --userspace) [[ $# -ge 2 ]] || die "--userspace needs a value"; userspace="$2"; shift 2 ;;
      --with-sdk) with_sdk=1; shift ;;
      --artifact-dir) [[ $# -ge 2 ]] || die "--artifact-dir needs a directory"; artifact_dir="$2"; shift 2 ;;
      -o|--output) [[ $# -ge 2 ]] || die "$1 needs a value"; output="$2"; shift 2 ;;
      --no-toolchain) tc_mode=none; shift ;;
      --distro-toolchain) tc_mode=distro; shift ;;
      --toolchain) [[ $# -ge 2 ]] || die "--toolchain needs a directory"; tc_mode=manual; tc_dir="$2"; shift 2 ;;
      *) die "unknown prepare option '$1'" ;;
    esac
  done
  set_active_arch "$arch"
  userspace="$(normalize_userspace_spec "$userspace")"
  if [[ "$userspace" == auto ]]; then
    case "$requested_target" in
      freebsd:*) userspace=busybox-static ;;
      upstream:*) if legacy_guest_busybox_target "$requested_target"; then userspace=busybox-static; else userspace=buildroot:minimal; fi ;;
      *) userspace=buildroot:minimal ;;
    esac
  fi
  target="$(effective_target_for_arch "$requested_target" "$ARCH")"
  mkdir -p "$EXPORTS"
  local provider="${target%%:*}" safe
  case "$provider" in
    upstream) ;;
    freebsd)
      iso_builder >/dev/null || die "FreeBSD preparation requires xorriso, genisoimage, or mkisofs on the staging machine (install before download/preparation)"
      [[ "$userspace" == busybox-static ]] || die "--userspace is a Linux-target option; FreeBSD carries its own userspace image"
      case "$ARCH" in
        x86_64|aarch64) ;;
        i386) die "FreeBSD/i386 is release-gated (14.x only) and its official VM images do not provide the bootstrap channel kernel-lab uses yet; use upstream Linux i386 for automated 32-bit x86 testing" ;;
        armv7) die "FreeBSD/armv7 uses board/GENERICSD media rather than the VM/cloud image kernel-lab needs for its automated control agent" ;;
        *) die "FreeBSD provider has not validated architecture '$ARCH'" ;;
      esac
      ;;
    custom) ;;
    *)
      # Provider declarations, not a core x86_64 special case, decide whether a
      # distro target architecture is valid and whether foreign-arch staging is
      # supported from this build worker.
      parse_target "$target"
      klab_provider_load "$provider"
      klab_provider_assert_arch "$provider" "$DISTRO_RELEASE" "$ARCH"
      ;;
  esac
  safe="$(printf '%s' "$requested_target" | tr ':@/' '___')"
  if [[ -z "$output" ]]; then
    if [[ -n "$artifact_dir" ]]; then output="${artifact_dir%/}/${safe}__${ARCH}__${profile}.klab"; else output="$EXPORTS/${safe}__${ARCH}__${profile}.klab"; fi
  fi
  [[ -z "$artifact_dir" ]] || mkdir -p "$artifact_dir"

  if [[ "$provider" == upstream ]]; then
    local raw="${target#upstream:}"
    [[ "$raw" != "$target" && -n "$raw" && "$raw" != *:* ]] || die "upstream target syntax: upstream:v6.6"
    if ! klab_arch_kernel_supported "$ARCH" "$raw"; then
      local __arch_min; __arch_min="$(arch_profile_field "$ARCH" KERNEL_MIN_VERSION 2>/dev/null || true)"
      die "upstream kernel $raw is not valid for architecture $ARCH${__arch_min:+ (minimum kernel $__arch_min)}"
    fi
    say "Preparing upstream $raw / $ARCH / $profile"
    prepare_build "$raw" "$profile" "$ARCH" >/dev/null
    if [[ "$userspace" == busybox-static && "$raw" == v2.[0-5].* ]]; then
      KLAB_GUEST_BUSYBOX_OVERRIDE="$(ensure_linux24_guest_busybox "$ARCH")"
    elif [[ "$userspace" == busybox-static ]] && legacy_guest_busybox_target "upstream:$raw"; then
      KLAB_GUEST_BUSYBOX_OVERRIDE="$(ensure_legacy_guest_busybox "$ARCH")"
    else
      ensure_guest_userspace "$userspace" "$ARCH" >/dev/null
    fi
    if (( with_sdk == 1 )); then [[ "$userspace" == buildroot:* ]] || die "--with-sdk requires --userspace buildroot:minimal, buildroot:network, or buildroot:ssh"; ensure_buildroot_sdk "$ARCH" "${userspace#buildroot:}" >/dev/null; fi
  else
    [[ "$profile" == normal ]] || die "--profile applies only to upstream targets"
    if [[ "$provider" == custom ]]; then
      parse_target "$target"
      local custom_env="$(bundle_dir_for "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$ARCH")/bundle.env"
      [[ -f "$custom_env" ]] || die "custom target is not registered locally: $target [$ARCH]. Run '$0 register-linux ...' first."
      unset BUNDLE_CUSTOM_MODE
      source "$custom_env"
      [[ "${BUNDLE_CUSTOM_MODE:-copy}" != reference ]] || die "custom target $target was registered with --reference and cannot be exported portably. Re-register it with --copy."
      say "Using registered custom Linux target $target [$ARCH]"
    else
      say "Fetching exact OS kernel artifacts for $target [$ARCH]"
      cmd_fetch "$target" >/dev/null
    # KLAB_BUILDENV_M2: capture an exact provider build root, but first resolve
    # and seal the toolchain that will be packaged with this target. The
    # .klabbuildenv stores the expected toolchain tree digest independently.
    case "${provider:-${target%%:*}}" in
      ubuntu|debian|fedora|centos|rhel|rocky|almalinux|alpine)
        if [[ "${tc_mode:-auto}" == none ]]; then
          say "Toolchain disabled; skipping hermetic .klabbuildenv capture for $target"
        else
          parse_target "$target"
          local __be_bundle __be_dir __be_file __be_id __be_tc_dir='' __be_tc_cc='' __be_tc_rel='' __be_tc_json='' __be_guard=''
          local __be_tc_tree='' __be_tc_family='' __be_tc_version='' __be_tc_target='' __be_dt_id='' __be_dt_file='' __be_dt_tmp='' __be_dt_line='' __be_req='' __be_req_family='' __be_req_version='' __be_req_banner=''
          __be_bundle="$(bundle_existing_dir_for "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "${ARCH:-x86_64}")"
          __be_dir="${artifact_dir:-$(dirname "$output")}"; mkdir -p "$__be_dir"
          __be_file="$__be_dir/buildenv-${PROVIDER}-${KERNEL_RELEASE}-${ARCH}--pending.klabbuildenv"
          # Distro kernels should default to their distribution-native compiler
          # artifact. Kernel.org nolibc crosstools are appropriate for upstream
          # builds, but many historical distro compiler patch versions are not
          # published there (e.g. Ubuntu GCC 4.6.3 / Fedora GCC 7.1.1).
          if [[ "${tc_mode:-auto}" == auto ]]; then
            tc_mode=distro
            say "Using distribution-native GCC/binutils for $target (automatic distro toolchain policy)"
          fi
          if [[ "${tc_mode:-auto}" == distro ]]; then
            __be_req="$(get_target_compiler_requirement "$target" 2>/dev/null || true)"
            [[ -n "$__be_req" ]] && IFS=$'\t' read -r __be_req_family __be_req_version __be_req_banner <<<"$__be_req"
            [[ -z "$__be_req_family" || "$__be_req_family" == gcc ]] || die "distro-native buildenv currently supports GCC kernels only"
            # Ubuntu and Debian publish one compiler package stream per release.
            # Re-capturing that authenticated closure for every kernel ABI is
            # expensive under foreign-architecture emulation and adds no fidelity.
            # Fedora remains target-specific because Koji is its compiler authority.
            local __be_dt_cache='' __be_dt_cache_fd='' __be_dt_major="${__be_req_version%%.*}"
            case "$PROVIDER" in
              ubuntu|debian)
                [[ "$__be_dt_major" =~ ^[0-9]+$ ]] || __be_dt_major=default
                __be_dt_cache="$KLAB_DISTRO_TOOLCHAIN_STORE/contracts/$PROVIDER/$DISTRO_RELEASE/$ARCH/gcc-$__be_dt_major.klabdistrotoolchain"
                mkdir -p "$(dirname "$__be_dt_cache")"
                exec {__be_dt_cache_fd}>"$__be_dt_cache.lock"
                flock "$__be_dt_cache_fd"
                ;;
            esac
            if [[ -n "$__be_dt_cache" && -s "$__be_dt_cache" ]] && \
               __be_dt_id="$($DISTRO_TOOLCHAIN_BIN verify "$__be_dt_cache" 2>/dev/null)" && \
               "$DISTRO_TOOLCHAIN_BIN" match-compiler "$__be_dt_cache" --version "$__be_req_version" --mode major-compatible >/dev/null 2>&1; then
              __be_dt_file="$__be_dt_cache"
              KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$DISTRO_TOOLCHAIN_BIN" import "$__be_dt_file" >/dev/null
              KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$DISTRO_TOOLCHAIN_BIN" assert-installed "$__be_dt_id" --provider "$PROVIDER" --release "$DISTRO_RELEASE" --arch "$ARCH" >/dev/null
              say "Reusing cached distribution-native GCC/binutils for $PROVIDER:$DISTRO_RELEASE [$ARCH, GCC $__be_dt_major]"
            else
              __be_dt_tmp="$(mktemp -d)"
              say "Capturing distribution-native GCC/binutils for $target [$ARCH]"
              KLAB_PROVIDER_TARGET_BUNDLE="$__be_bundle" KLAB_PROVIDER_KERNEL_RELEASE="$KERNEL_RELEASE" \
                klab_provider_capture_toolchain "$PROVIDER" "$DISTRO_RELEASE" "$__be_dt_tmp" "$ARCH" "$__be_req_version"
              __be_dt_file="$__be_dir/distro-toolchain-${PROVIDER}-${DISTRO_RELEASE}-${ARCH}--pending.klabdistrotoolchain"
              local __be_dt_prov=()
              [[ ! -f "$__be_dt_tmp/provenance.json" ]] || __be_dt_prov=(--provenance "$__be_dt_tmp/provenance.json")
              __be_dt_line="$($DISTRO_TOOLCHAIN_BIN create --packages "$__be_dt_tmp/packages" --inventory "$__be_dt_tmp/packages.tsv" --compiler-json "$__be_dt_tmp/compiler.json" "${__be_dt_prov[@]}" --provider "$PROVIDER" --release "$DISTRO_RELEASE" --arch "$ARCH" -o "$__be_dt_file")"
              __be_dt_id="${__be_dt_line%%$'\t'*}"
              local __be_dt_final="$__be_dir/distro-toolchain-${PROVIDER}-${DISTRO_RELEASE}-${ARCH}--${__be_dt_id:0:16}.klabdistrotoolchain"
              mv -f "$__be_dt_file" "$__be_dt_final"; __be_dt_file="$__be_dt_final"
              if [[ -n "$__be_dt_cache" ]]; then
                cp -f "$__be_dt_file" "$__be_dt_cache.tmp.$$"
                mv -f "$__be_dt_cache.tmp.$$" "$__be_dt_cache"
              fi
              rm -rf "$__be_dt_tmp"
            fi
            # Keep the traditional sibling transfer artifact even when the
            # content is served from the shared contract cache. A hard link is
            # free on one filesystem; reflink/copy is the portable fallback.
            if [[ -n "$__be_dt_cache" && "$__be_dt_file" == "$__be_dt_cache" ]]; then
              local __be_dt_sibling="$__be_dir/distro-toolchain-${PROVIDER}-${DISTRO_RELEASE}-${ARCH}--${__be_dt_id:0:16}.klabdistrotoolchain"
              if [[ ! -s "$__be_dt_sibling" ]]; then
                ln "$__be_dt_cache" "$__be_dt_sibling" 2>/dev/null || cp --reflink=auto "$__be_dt_cache" "$__be_dt_sibling"
              fi
              __be_dt_file="$__be_dt_sibling"
            fi
            if [[ -n "$__be_req_version" ]]; then
              if ! "$DISTRO_TOOLCHAIN_BIN" match-compiler "$__be_dt_file" --version "$__be_req_version" --mode exact >/dev/null 2>&1; then
                case "$PROVIDER" in
                  ubuntu|debian)
                    "$DISTRO_TOOLCHAIN_BIN" match-compiler "$__be_dt_file" --version "$__be_req_version" --mode major-compatible >/dev/null || die "captured distro compiler is incompatible with kernel compiler $__be_req_version"
                    say "Using same-major distro GCC fallback for $target; exact $__be_req_version is unavailable and module compile/load validation remains mandatory"
                    ;;
                  *) "$DISTRO_TOOLCHAIN_BIN" match-compiler "$__be_dt_file" --version "$__be_req_version" --mode exact >/dev/null ;;
                esac
              fi
            fi
            KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$DISTRO_TOOLCHAIN_BIN" import "$__be_dt_file" >/dev/null
            [[ -z "$__be_dt_cache_fd" ]] || { flock -u "$__be_dt_cache_fd"; exec {__be_dt_cache_fd}>&-; }
            KLAB_PROVIDER_TARGET_BUNDLE="$__be_bundle" KLAB_BUILDENV_REQUIRED_GCC_VERSION="$__be_req_version" \
              KLAB_BUILDENV_COMPILER_CONTRACT=distro-native-v1 KLAB_BUILDENV_STAGING_MODE=provider-native-v1 \
              KLAB_BUILDENV_DISTRO_TOOLCHAIN_ID="$__be_dt_id" KLAB_BUILDENV_DISTRO_TOOLCHAIN_FILE="$__be_dt_file" \
              klab_provider_capture_buildenv "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$__be_bundle" "$__be_file" "$ARCH" >/dev/null
          else
            if [[ "${tc_mode:-auto}" == manual ]]; then
              __be_tc_dir="$(readlink -f "$tc_dir")"
            else
              __be_tc_dir="$(KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" KLAB_ARCH="${ARCH:-x86_64}" "$0" toolchain ensure "$target" "$profile")"
              tc_mode=manual; tc_dir="$__be_tc_dir"
            fi
            [[ -d "$__be_tc_dir" ]] || die "resolved toolchain directory missing: $__be_tc_dir"
            if [[ -f "$__be_tc_dir/.klab-resolver.env" ]]; then
              unset KLAB_TOOLCHAIN_CC
              source "$__be_tc_dir/.klab-resolver.env"
              __be_tc_cc="${KLAB_TOOLCHAIN_CC:-}"
            fi
            if [[ -z "$__be_tc_cc" || "$__be_tc_cc" != "$__be_tc_dir"/* ]]; then
              __be_tc_cc="$(find "$__be_tc_dir" -maxdepth 8 \( -type f -o -type l \) -perm -111 \( -name '*-gcc' -o -name gcc \) -print 2>/dev/null | sort | head -n1 || true)"
            fi
            [[ -n "$__be_tc_cc" && -x "$__be_tc_cc" ]] || die "could not locate GCC inside toolchain $__be_tc_dir"
            __be_tc_rel="${__be_tc_cc#"$__be_tc_dir"/}"
            __be_guard="${KLAB_TOOLCHAIN_BOUNDARY_BIN:-$SELF_DIR/klab-toolchain-boundary.sh}"
            __be_tc_json="$("$__be_guard" seal --root "$__be_tc_dir" --cc "$__be_tc_rel" --json)"
            IFS=$'\t' read -r __be_tc_tree __be_tc_family __be_tc_version __be_tc_target < <(python3 - "$__be_tc_json" <<'PY_BE_TC'
import json,sys
m=json.loads(sys.argv[1]); print('\t'.join(str(m.get(k,'')) for k in ('tree_sha256','family','version','target')))
PY_BE_TC
            )
            KLAB_BUILDENV_TOOLCHAIN_ROOT="$__be_tc_dir" KLAB_BUILDENV_TOOLCHAIN_JSON="$__be_tc_json" KLAB_BUILDENV_TOOLCHAIN_TREE_SHA256="$__be_tc_tree" \
              KLAB_BUILDENV_TOOLCHAIN_FAMILY="$__be_tc_family" KLAB_BUILDENV_TOOLCHAIN_VERSION="$__be_tc_version" KLAB_BUILDENV_TOOLCHAIN_TARGET="$__be_tc_target" KLAB_BUILDENV_TOOLCHAIN_CC_REL="$__be_tc_rel" \
              klab_provider_capture_buildenv "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$__be_bundle" "$__be_file" "$ARCH" >/dev/null
          fi
          __be_id="$($BUILDENV_BIN verify "$__be_file" --deep)"
          local __be_final="$__be_dir/buildenv-${PROVIDER}-${KERNEL_RELEASE}-${ARCH}--${__be_id:0:16}.klabbuildenv"
          mv -f "$__be_file" "$__be_final"
          KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" import "$__be_final" >/dev/null
          { grep -v -E '^BUNDLE_(BUILDENV|DISTRO_TOOLCHAIN)_' "$__be_bundle/bundle.env" 2>/dev/null || true; } >"$__be_bundle/bundle.env.tmp"
          printf 'BUNDLE_BUILDENV_ID=%q\nBUNDLE_BUILDENV_FILE=%q\n' "$__be_id" "$__be_final" >>"$__be_bundle/bundle.env.tmp"
          [[ -z "$__be_dt_id" ]] || printf 'BUNDLE_DISTRO_TOOLCHAIN_ID=%q\nBUNDLE_DISTRO_TOOLCHAIN_FILE=%q\n' "$__be_dt_id" "$__be_dt_file" >>"$__be_bundle/bundle.env.tmp"
          mv "$__be_bundle/bundle.env.tmp" "$__be_bundle/bundle.env"
        fi
        ;;
    esac

    fi
    [[ "$(target_backend "$target")" == linux ]] && ensure_guest_userspace "$userspace" "$ARCH" >/dev/null
    if (( with_sdk == 1 )); then [[ "$userspace" == buildroot:* ]] || die "--with-sdk requires --userspace buildroot:minimal, buildroot:network, or buildroot:ssh"; ensure_buildroot_sdk "$ARCH" "${userspace#buildroot:}" >/dev/null; fi
  fi

  local args=(create "$target" --profile "$profile" -o "$output")
  local backend; backend="$(target_backend "$target")"
  [[ "$backend" == linux ]] && args+=(--userspace "$userspace")
  (( with_sdk == 1 )) && args+=(--include-sdk)
  case "$backend:$tc_mode" in
    freebsd:auto|freebsd:none) ;;
    freebsd:manual) die "FreeBSD module builds use the compiler/toolchain inside the FreeBSD target image; --toolchain is Linux-only" ;;
    *:auto) args+=(--auto-toolchain) ;;
    *:manual) args+=(--include-toolchain "$tc_dir") ;;
    *:distro) ;;
    *:none) ;;
  esac
  bundle_tool "${args[@]}"
  say "Ready for transfer: $output"
  printf '%s\n' "$output"
}

cmd_import_bundle() {
  # Directory imports are the air-gap transfer contract: install reusable
  # dependencies first, then every target bundle. Never pass the directory
  # itself to klab-bundle.sh, which accepts only a FILE.klab.
  if [[ $# -ge 1 && -d "$1" ]]; then
    local __dir="$1" __force="" __load_image="" __arg __f __count=0
    for __arg in "${@:2}"; do
      case "$__arg" in
        --force) __force=--force ;;
        --load-image) __load_image=--load-image ;;
        *) die "unknown directory import option '$__arg'" ;;
      esac
    done

    # Typed shared artifacts predate .klabbuildenv and are imported through
    # klab-artifact.sh when present in a transfer directory.
    local __artifact_bin="${KLAB_ARTIFACT_BIN:-$SELF_DIR/klab-artifact.sh}"
    if [[ -x "$__artifact_bin" ]]; then
      while IFS= read -r -d '' __f; do
        if [[ -n "$__force" ]]; then KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$__artifact_bin" import "$__f" --force >/dev/null
        else KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$__artifact_bin" import "$__f" >/dev/null; fi
        __count=$((__count + 1))
      done < <(find "$__dir" -maxdepth 1 -type f \( -name '*.klabtoolchain' -o -name '*.klabrootfs' -o -name '*.klabsdk' -o -name '*.klabfirmware' -o -name '*.klabsource' \) -print0 | sort -z)
    fi

    # Distribution-native compiler/binutils package artifacts are separate
    # from relocatable shared .klabtoolchain objects. Import them before the
    # buildenv/target that may reference their content ID.
    while IFS= read -r -d '' __f; do
      if [[ -n "$__force" ]]; then KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$DISTRO_TOOLCHAIN_BIN" import "$__f" --force >/dev/null
      else KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$DISTRO_TOOLCHAIN_BIN" import "$__f" >/dev/null; fi
      __count=$((__count + 1))
    done < <(find "$__dir" -maxdepth 1 -type f -name '*.klabdistrotoolchain' -print0 | sort -z)

    # M2 exact distro build roots must exist before thin target import.
    while IFS= read -r -d '' __f; do
      if [[ -n "$__force" ]]; then KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" import "$__f" --force >/dev/null
      else KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" import "$__f" >/dev/null; fi
      __count=$((__count + 1))
    done < <(find "$__dir" -maxdepth 1 -type f -name '*.klabbuildenv' -print0 | sort -z)

    # Targets are last because they may reference any of the objects above.
    while IFS= read -r -d '' __f; do
      local __bundle_args=(import "$__f")
      [[ -n "$__force" ]] && __bundle_args+=(--force)
      [[ -n "$__load_image" ]] && __bundle_args+=(--load-image)
      bundle_tool "${__bundle_args[@]}" >/dev/null
      __count=$((__count + 1))
    done < <(find "$__dir" -maxdepth 1 -type f -name '*.klab' -print0 | sort -z)

    ((__count > 0)) || die "transfer directory contains no importable KLab artifacts: $__dir"
    say "Imported transfer directory: $__dir"
    return
  elif [[ $# -ge 1 && "$1" == *.klabdistrotoolchain ]]; then
    local __dt_force="" __arg
    for __arg in "${@:2}"; do case "$__arg" in --force) __dt_force=--force ;; *) die "unknown .klabdistrotoolchain import option '$__arg'" ;; esac; done
    if [[ -n "$__dt_force" ]]; then KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$DISTRO_TOOLCHAIN_BIN" import "$1" --force
    else KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$DISTRO_TOOLCHAIN_BIN" import "$1"; fi
    return
  elif [[ $# -ge 1 && "$1" == *.klabbuildenv ]]; then
    local __be_force="" __arg
    for __arg in "${@:2}"; do
      case "$__arg" in --force) __be_force=--force ;; --load-image) : ;; *) die "unknown .klabbuildenv import option '$__arg'" ;; esac
    done
    if [[ -n "$__be_force" ]]; then KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" import "$1" --force
    else KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" import "$1"; fi
    return
  fi
  (($# >= 1)) || die "usage: $0 import FILE.klab|DIRECTORY [--force] [--load-image]"
  bundle_tool import "$@"
}

cmd_verify_bundle() { (($# == 1)) || die "usage: $0 verify FILE.klab"; bundle_tool verify "$1"; }
cmd_inspect_bundle() { (($# == 1)) || die "usage: $0 inspect FILE.klab"; bundle_tool inspect "$1"; }

normalize_version() {
  case "$1" in
    mainline|master) printf '%s\n' mainline ;;
    v*) printf '%s\n' "$1" ;;
    *) printf 'v%s\n' "$1" ;;
  esac
}

legacy_tarball_release() {
  local version="${1#v}" minor
  [[ "$version" =~ ^2\.(0|2|4|6)\. ]] || return 1
  minor="${BASH_REMATCH[1]}"
  # Git-imported kernel history begins at 2.6.12. Prefer Git whenever a tag
  # exists; this path supplies the official archives for older releases.
  if [[ "$minor" == 6 ]]; then
    local sub="${version#2.6.}"; sub="${sub%%.*}"
    [[ "$sub" =~ ^[0-9]+$ ]] && (( 10#$sub < 12 )) || return 1
  fi
  printf '%s\n' "$version"
}

fetch_legacy_tarball_identity() {
  local requested="$1" version series base file cache sums expected actual
  version="$(legacy_tarball_release "$requested")" || return 1
  series="v$(printf '%s' "$version" | cut -d. -f1,2)"
  base="https://cdn.kernel.org/pub/linux/kernel/$series"
  file="linux-$version.tar.xz"
  cache="$KLAB_CACHE/upstream-tarballs/$file"
  sums="$KLAB_CACHE/upstream-tarballs/$series-sha256sums.asc"
  mkdir -p "$(dirname "$cache")"
  if [[ ! -s "$sums" ]]; then
    [[ "$OFFLINE" != 1 ]] || die "offline mode: checksum index is missing for legacy kernel $requested"
    download_url "$base/sha256sums.asc" "$sums"
  fi
  expected="$(awk -v f="$file" '$2==f {print $1; exit}' "$sums")"
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || die "kernel.org checksum index has no entry for $file"
  if [[ ! -s "$cache" ]]; then
    [[ "$OFFLINE" != 1 ]] || die "offline mode: legacy kernel tarball is missing: $cache"
    say "Fetching kernel.org legacy tarball $file"
    download_url "$base/$file" "$cache"
  fi
  actual="$(sha256sum "$cache" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "checksum mismatch for kernel.org legacy tarball $file"
  printf 'tarball:%s\n' "$actual"
}

fetch_ref_commit() {
  local requested="$1" ref err1 err2 rc1=0 rc2=0 detail network=0
  [[ -d "$SRC/.git" ]] || die "run '$0 init --staging' first"

  if [[ "$requested" == mainline ]]; then
    say "Fetching current mainline"
    err1="$(mktemp)"
    if ! git -C "$SRC" fetch --depth=1 -q mainline master 2>"$err1"; then
      detail="$(tail -n 8 "$err1" 2>/dev/null || true)"; rm -f "$err1"
      die "failed to fetch current mainline (network/remote error):\n$detail"
    fi
    rm -f "$err1"; ref=FETCH_HEAD
  else
    say "Fetching $requested"
    if ! git -C "$SRC" show-ref --verify --quiet "refs/tags/$requested"; then
      err1="$(mktemp)"; err2="$(mktemp)"
      git -C "$SRC" fetch --depth=1 -q stable "refs/tags/$requested:refs/tags/$requested" 2>"$err1" || rc1=$?
      if (( rc1 != 0 )); then git -C "$SRC" fetch --depth=1 -q mainline "refs/tags/$requested:refs/tags/$requested" 2>"$err2" || rc2=$?; fi
      if (( rc1 != 0 && rc2 != 0 )); then
        detail="$(cat "$err1" "$err2" 2>/dev/null | tail -n 16)"
        grep -Eiq 'could not resolve|connection refused|timed out|network is unreachable|connection reset|TLS|SSL|proxy|failed to connect|temporary failure' "$err1" "$err2" 2>/dev/null && network=1 || true
        rm -f "$err1" "$err2"
        if (( network == 1 )); then die "network/remote failure while fetching kernel tag '$requested':\n$detail"; fi
        if legacy_tarball_release "$requested" >/dev/null 2>&1; then
          fetch_legacy_tarball_identity "$requested"
          return
        fi
        die "kernel tag '$requested' was not found in the configured stable or mainline remotes:\n$detail"
      fi
      rm -f "$err1" "$err2"
    fi
    ref="refs/tags/$requested"
  fi
  local resolved
  if resolved="$(git -C "$SRC" rev-parse "$ref^{commit}" 2>/dev/null)"; then
    printf '%s\n' "$resolved"
    return
  fi
  # v2.6.11 is an historical exception: its tag is a tree object.
  local tree
  tree="$(git -C "$SRC" rev-parse "$ref^{tree}" 2>/dev/null || true)"
  [[ "$tree" =~ ^[0-9a-f]{40,64}$ ]] || die "kernel tag $requested does not resolve to a commit or tree"
  printf "tree:%s\n" "$tree"
}

source_key() {
  local version="$1" commit="$2"
  if [[ "$version" == mainline ]]; then
    printf 'mainline-%s\n' "${commit:0:12}"
  else
    printf '%s\n' "${version#v}"
  fi
}

materialize_source() {
  local version="$1" commit="$2" key dir marker
  key="$(source_key "$version" "$commit")"
  dir="$SOURCES/$key"
  marker="$dir/.klab-source-commit"
  if [[ -f "$marker" && "$(cat "$marker")" == "$commit" && -f "$dir/Makefile" ]]; then
    printf '%s\n' "$dir"
    return
  fi
  if [[ -e "$dir" ]]; then chmod -R u+w "$dir" 2>/dev/null || true; rm -rf "$dir"; fi
  mkdir -p "$dir"
  say "Materializing immutable source tree $dir"
  if [[ "$commit" == tarball:* ]]; then
    local release="${version#v}" archive="$KLAB_CACHE/upstream-tarballs/linux-${version#v}.tar.xz"
    [[ -s "$archive" ]] || die "cached legacy source archive is missing: $archive"
    [[ "$(sha256sum "$archive" | awk '{print $1}')" == "${commit#tarball:}" ]] || die "cached legacy source archive checksum changed: $archive"
    tar -xJf "$archive" --strip-components=1 -C "$dir"
  elif [[ "$commit" == tree:* ]]; then
    local tree="${commit#tree:}"
    [[ -d "$SRC/.git" ]] || die "immutable source tree is missing for $version ($commit), and no local kernel object store is available"
    git -C "$SRC" cat-file -e "$tree^{tree}" 2>/dev/null || die "source tree $tree is missing from the local kernel object store"
    git -C "$SRC" archive --format=tar "$tree" | tar -xf - -C "$dir"
  else
    [[ -d "$SRC/.git" ]] || die "immutable source tree is missing for $version ($commit), and no local kernel object store is available"
    git -C "$SRC" cat-file -e "$commit^{commit}" 2>/dev/null || die "source commit $commit is missing from the local kernel object store"
    git -C "$SRC" archive --format=tar "$commit" | tar -xf - -C "$dir"
  fi
  printf '%s\n' "$commit" > "$marker"
  chmod -R a-w "$dir" 2>/dev/null || true
  # Kbuild itself only reads the source tree when O= points elsewhere. Keep the
  # tree immutable to make concurrent builds/tests safe and obvious.
  printf '%s\n' "$dir"
}

source_for_cached_build() {
  local build="$1" raw="${2:-}" commit version source
  if [[ -f "$build/.klab-source-dir" ]]; then
    source="$(cat "$build/.klab-source-dir")"
    [[ -d "$source" && -f "$source/Makefile" ]] || die "cached build references missing immutable source tree: $source"
    printf '%s\n' "$source"
    return
  fi
  [[ -f "$build/.klab-commit" ]] || die "cached build lacks source metadata: $build"
  commit="$(cat "$build/.klab-commit")"
  if [[ -n "$raw" ]]; then version="$(normalize_version "$raw")"; else version="v$(basename "$build" | sed 's/__.*$//')"; fi
  source="$(materialize_source "$version" "$commit")"
  printf '%s\n' "$source" > "$build/.klab-source-dir"
  printf '%s\n' "$source"
}

build_key() {
  local version="$1" profile="$2" commit="$3" arch="$(canonical_arch "${4:-$ARCH}")"
  if [[ "$version" == mainline ]]; then
    printf 'mainline-%s__%s__%s\n' "${commit:0:12}" "$arch" "$profile"
  else
    printf '%s__%s__%s\n' "${version#v}" "$arch" "$profile"
  fi
}

config_legacy_set() {
  local config="$1" opt="$2" mode="$3" value="${4:-}"
  python3 - "$config" "$opt" "$mode" "$value" <<'PYCONFIG'
from pathlib import Path
import json,re,sys
path,opt,mode,value=sys.argv[1:]
path=Path(path)
lines=path.read_text().splitlines() if path.exists() else []
pat=re.compile(r'^(?:'+re.escape(opt)+r'=|# '+re.escape(opt)+r' is not set$)')
lines=[line for line in lines if not pat.match(line)]
if mode=='enable': lines.append(opt+'=y')
elif mode=='disable': lines.append('# '+opt+' is not set')
elif mode=='string': lines.append(opt+'='+json.dumps(value))
elif mode=='value': lines.append(opt+'='+value)
else: raise SystemExit('unknown config edit mode: '+mode)
path.write_text('\n'.join(lines)+'\n')
PYCONFIG
}
config_enable() {
  local source="$1" config="$2" opt="$3"
  if [[ -x "$source/scripts/config" ]]; then "$source/scripts/config" --file "$config" --enable "$opt"; else config_legacy_set "$config" "$opt" enable; fi
}
config_disable() {
  local source="$1" config="$2" opt="$3"
  if [[ -x "$source/scripts/config" ]]; then "$source/scripts/config" --file "$config" --disable "$opt" 2>/dev/null || true; else config_legacy_set "$config" "$opt" disable; fi
}
config_string() {
  local source="$1" config="$2" opt="$3" val="$4"
  if [[ -x "$source/scripts/config" ]]; then "$source/scripts/config" --file "$config" --set-str "$opt" "$val" 2>/dev/null || true; else config_legacy_set "$config" "$opt" string "$val"; fi
}
config_value() {
  local source="$1" config="$2" opt="$3" val="$4"
  if [[ -x "$source/scripts/config" ]]; then "$source/scripts/config" --file "$config" --set-val "$opt" "$val" 2>/dev/null || true; else config_legacy_set "$config" "$opt" value "$val"; fi
}

ensure_legacy_gcc_runtime() {
  local tc="$1" cc="$2" envfile="$tc/.klab-runtime-libs.env"
  local url="https://old-releases.ubuntu.com/ubuntu/pool/main/m/mpfr4/libmpfr4_3.1.6-1_amd64.deb"
  local expected="de22baf3dd851a10e16fbf66a243e70149ca46e06b2939fdc79429196cefc090"
  local runtime="$tc/runtime-libs" tmp actual libdir
  KLAB_BUILD_LIBRARY_PATH=""
  if [[ -f "$envfile" ]]; then
    unset KLAB_LEGACY_RUNTIME_LIBRARY_PATH
    source "$envfile"
    libdir="${KLAB_LEGACY_RUNTIME_LIBRARY_PATH:-}"
    if [[ -n "$libdir" && -e "$libdir/libmpfr.so.4" ]]; then
      KLAB_BUILD_LIBRARY_PATH="$libdir"
      return 0
    fi
  fi
  if printf 'int x;\n' | LD_LIBRARY_PATH= "$cc" -x c -c -o /dev/null - >/dev/null 2>&1; then return 0; fi
  [[ "$(host_arch)" == x86_64 ]] || die "legacy GCC runtime closure is not implemented for host $(host_arch)"
  [[ "$OFFLINE" != 1 ]] || die "offline mode: legacy GCC runtime library artifact is missing"
  have dpkg-deb || die "dpkg-deb is required to capture the legacy GCC runtime closure"
  tmp="$(mktemp -d)"
  download_url "$url" "$tmp/libmpfr4.deb"
  actual="$(sha256sum "$tmp/libmpfr4.deb" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || { rm -rf "$tmp"; die "legacy MPFR runtime checksum mismatch"; }
  rm -rf "$runtime"; mkdir -p "$runtime"
  dpkg-deb -x "$tmp/libmpfr4.deb" "$runtime"
  rm -rf "$tmp"
  libdir="$runtime/usr/lib/x86_64-linux-gnu"
  [[ -e "$libdir/libmpfr.so.4" ]] || die "captured legacy MPFR package lacks libmpfr.so.4"
  {
    printf 'KLAB_LEGACY_RUNTIME_LIBRARY_PATH=%q\n' "$libdir"
    printf 'KLAB_LEGACY_RUNTIME_URL=%q\n' "$url"
    printf 'KLAB_LEGACY_RUNTIME_SHA256=%q\n' "$actual"
  } > "$envfile"
  KLAB_BUILD_LIBRARY_PATH="$libdir"
}

setup_upstream_build_toolchain() {
  local arch="$(canonical_arch "$1")" source="${2:-}" karch tc cc hv kernel_major="" kernel_patch="" legacy_gcc=4.9.4 hostkey target legacy_id cross_prefix
  KLAB_BUILD_PATH="$PATH"
  KLAB_BUILD_MAKE_ARGS=("ARCH=$(linux_karch_for_source "$arch" "$source")")

  # Linux 2.x, 4.x, and 3.0-3.10 use sealed historical compilers.
  # Linux 3.11+ uses the proven host compiler path plus scoped early-boot fixes.
  if [[ -n "$source" && -f "$source/Makefile" ]]; then
    kernel_major="$(sed -n 's/^VERSION[[:space:]]*=[[:space:]]*//p' "$source/Makefile" | head -n1)"
    kernel_patch="$(sed -n 's/^PATCHLEVEL[[:space:]]*=[[:space:]]*//p' "$source/Makefile" | head -n1).$(sed -n 's/^SUBLEVEL[[:space:]]*=[[:space:]]*//p' "$source/Makefile" | head -n1)"
  fi
  if [[ "$kernel_major" =~ ^(2|4)$ ]] ||
     { [[ "$kernel_major" == 3 && "${kernel_patch%%.*}" =~ ^[0-9]+$ ]] &&
       (( ${kernel_patch%%.*} <= 10 )); }; then
    hostkey="$(crosstool_host_name "$(host_arch)")" || die "no kernel.org legacy compiler for host $(host_arch)"
    target="$(toolchain_target_name "$arch")"
    if [[ "$kernel_major" == 2 && ( "$kernel_patch" == 6.0 || "$kernel_patch" =~ ^6\.([0-9]+)$ && ${BASH_REMATCH[1]} -le 11 || "$kernel_patch" == 4.* || "$kernel_patch" == 2.* || "$kernel_patch" == 0.* ) && ( "$arch" == x86_64 || "$arch" == i386 ) ]]; then
      if [[ "$arch" == i386 ]]; then legacy_id=debian-gcc-3.3.6-i386; else legacy_id=debian-gcc-3.3.6-amd64; fi
      tc="$TOOLCHAINS/$legacy_id"
      [[ -f "$tc/.klab-resolver.env" ]] || die "legacy compiler artifact is missing: $legacy_id"
    elif [[ "$kernel_major" == 2 && "$kernel_patch" =~ ^6\.([0-9]+)$ ]] && (( ${BASH_REMATCH[1]} <= 16 )) && [[ "$arch" == x86_64 ]]; then
      legacy_id=debian-gcc-4.1.2-amd64
      tc="$TOOLCHAINS/$legacy_id"
      [[ -f "$tc/.klab-resolver.env" ]] || die "legacy compiler artifact is missing: $legacy_id"
    else
      legacy_id="kernelorg-gcc-${legacy_gcc}-${hostkey}-to-${target}"
      tc="$TOOLCHAINS/$legacy_id"
      if [[ ! -f "$tc/.klab-resolver.env" ]]; then
        [[ "$OFFLINE" != 1 ]] || die "offline mode: legacy compiler artifact is missing: $legacy_id"
        tc="$(fetch_kernelorg_gcc "$legacy_gcc" "$arch")"
      fi
    fi
    unset KLAB_TOOLCHAIN_CC
    source "$tc/.klab-resolver.env"
    cc="${KLAB_TOOLCHAIN_CC:-}"
    [[ -x "$cc" ]] || die "legacy compiler artifact has no executable GCC: $tc"
    if [[ "$legacy_id" == kernelorg-* ]]; then
      ensure_legacy_gcc_runtime "$tc" "$cc"
      cross_prefix="${cc%gcc}"
    else
      # The archived Debian compiler is paired with its in-root binutils.
      # Old kernel makefiles may invoke as/ld directly, bypassing the GCC
      # wrapper, so expose the sealed binutils runtime for the whole build.
      KLAB_BUILD_LIBRARY_PATH="$tc/usr/lib:$tc/usr/lib/x86_64-linux-gnu"
      # CC is absolute and its wrapper prepends the archived binutils itself.
      # Keep host utilities on the host PATH so modern HOSTCC output is not
      # sent to the 2006 assembler (which predates CET/endbr64).
      KLAB_BUILD_PATH="$PATH"
      # Preserve makefile-added flags such as `OBJCOPY += -O binary`. Passing
      # individual binutils variables on make's command line suppresses those
      # historical assignments, so bind the sealed wrappers by prefix instead.
      cross_prefix="$tc/bin/"
    fi
    if [[ "$legacy_id" == kernelorg-* ]]; then KLAB_BUILD_PATH="$(dirname "$cc"):$PATH"; fi
    # Linux 2.0/2.2 append -D__KERNEL__ and -I$(HPATH) directly to their
    # recursive CC variable. A command-line CC= assignment suppresses that
    # historical Makefile suffix and leaks compilation into host headers.
    if [[ "$kernel_patch" != 2.* && "$kernel_patch" != 0.* ]]; then
      KLAB_BUILD_MAKE_ARGS+=("CC=$cc")
    fi
    KLAB_BUILD_MAKE_ARGS+=("HOSTCC=$(command -v gcc)" "PERL=$SELF_DIR/lib/legacy-kernel-perl" "CROSS_COMPILE=$cross_prefix")
    if [[ "$kernel_major" == 2 ]]; then
      # Linux 2.x host tools need non-PIE and modern libc compatibility
      # flags. Linux 3.x/4.x supply generated architecture include paths
      # through their own HOSTCFLAGS; replacing them breaks host tools.
      KLAB_BUILD_MAKE_ARGS+=("HOSTCFLAGS=-fno-pie -no-pie -fgnu89-inline -include limits.h -include locale.h -Iinclude2 -I$source/include" "HOSTLDFLAGS=-no-pie")
    fi
    say "Building Linux ${kernel_major}.x for $arch with stored $(basename "$tc")"
    return 0
  fi
  if [[ "$arch" == "$(host_arch)" ]]; then
    have gcc || die "native upstream build requires gcc"
    KLAB_BUILD_MAKE_ARGS+=("CC=$(command -v gcc)")
    if [[ -f "$source/kernel/timeconst.pl" ]] && grep -Fq 'defined(@' "$source/kernel/timeconst.pl"; then
      KLAB_BUILD_MAKE_ARGS+=("PERL=$SELF_DIR/lib/legacy-kernel-perl")
    fi
    return 0
  fi
  local cthost
  cthost="$(crosstool_host_name "$(host_arch)")" || die "kernel.org does not publish a prebuilt kernel crosstool for this staging host architecture ($(host_arch)); install an explicit cross compiler for $arch"
  hv="$(gcc -dumpfullversion -dumpversion 2>/dev/null | head -n1 || gcc -dumpversion 2>/dev/null | head -n1)"
  [[ -n "$hv" ]] || die "could not determine host GCC version for cross-toolchain selection"
  tc="$(fetch_kernelorg_gcc "$hv" "$arch")"
  unset KLAB_TOOLCHAIN_CC
  # shellcheck disable=SC1090
  source "$tc/.klab-resolver.env"
  cc="${KLAB_TOOLCHAIN_CC:-}"
  [[ -x "$cc" ]] || die "cross-toolchain compiler missing after fetch: $cc"
  KLAB_BUILD_PATH="$(dirname "$cc"):$PATH"
  KLAB_BUILD_MAKE_ARGS+=("CC=$cc" "CROSS_COMPILE=${cc%gcc}")
  say "Cross-building upstream kernel for $arch with $(basename "$cc")"
}

upstream_make() { PATH="$KLAB_BUILD_PATH" LD_LIBRARY_PATH="${KLAB_BUILD_LIBRARY_PATH:-${LD_LIBRARY_PATH:-}}" make "${KLAB_BUILD_MAKE_ARGS[@]}" "$@"; }

prepare_legacy_make_compat_source() {
  local source="$1" version="$2" makefile="$source/Makefile" out tmp needs_make4=0 needs_e820=0 needs_memmap_holes=0 needs_kconfig260=0 needs_force_order=0 needs_plt32=0 needs_percpu_reloc_static=0 needs_unlzo_header_static=0 needs_x86cpu_device_alias=0 needs_i915_inline_static=0 needs_acpi_osi_initdata=0 needs_realmode_no_pic=0 needs_static_call_compat=0 needs_gcc_header_fallback=0 needs_x86_segment_mov=0 needs_copy_user_size=0 needs_compressed_host_flags=0 needs_compressed_memcpy=0 needs_extract_overlap=0 needs_bootdata_mapping=0 force_order_defs=0
  [[ -f "$makefile" ]] || { printf '%s\n' "$source"; return; }
  grep -Fq 'config %config: scripts_basic outputmakefile FORCE' "$makefile" && needs_make4=1
  [[ "$version" == v2.6.12 ]] && needs_e820=1
  [[ "$version" =~ ^v2\.6\.(12|13|14)$ ]] && needs_memmap_holes=1
  if [[ -f "$source/scripts/kconfig/mconf.c" ]] &&
     grep -Fq "static struct menu *current_menu;" "$source/scripts/kconfig/mconf.c" &&
     grep -Rqs "extern struct menu \*current_menu;" "$source/scripts/kconfig"; then
    needs_kconfig260=1
  fi
  if [[ -d "$source/arch/x86/boot/compressed" ]]; then
    force_order_defs="$(grep -l '^unsigned long __force_order;$' "$source"/arch/x86/boot/compressed/*.c 2>/dev/null | wc -l)"
    (( force_order_defs > 1 )) && needs_force_order=1
  fi
  if [[ -f "$source/arch/x86/tools/relocs.c" ]] &&
     grep -Fq 'case R_X86_64_PC32:' "$source/arch/x86/tools/relocs.c" &&
     ! grep -Fq 'case R_X86_64_PLT32:' "$source/arch/x86/tools/relocs.c"; then
    needs_plt32=1
  fi
  if [[ -f "$source/arch/x86/tools/relocs.c" ]] &&
     grep -Fq 'Elf_Addr per_cpu_load_addr;' "$source/arch/x86/tools/relocs.c" &&
     ! grep -Fq 'static Elf_Addr per_cpu_load_addr;' "$source/arch/x86/tools/relocs.c"; then
    needs_percpu_reloc_static=1
  fi
  if [[ -f "$source/lib/decompress_unlzo.c" ]] &&
     grep -Eq '^STATIC inline (int|long) INIT parse_header' "$source/lib/decompress_unlzo.c"; then
    needs_unlzo_header_static=1
  fi
  if [[ -f "$source/include/linux/mod_devicetable.h" ]] &&
     grep -Fq 'struct x86_cpu_id {' "$source/include/linux/mod_devicetable.h" &&
     ! grep -Fq '#define x86cpu_device_id x86_cpu_id' "$source/include/linux/mod_devicetable.h"; then
    needs_x86cpu_device_alias=1
  fi
  if [[ -f "$source/drivers/gpu/drm/i915/i915_drv.h" ]] &&
     grep -Fq 'extern inline bool intel_gmbus_is_port_valid' "$source/drivers/gpu/drm/i915/i915_drv.h"; then
    needs_i915_inline_static=1
  fi
  if [[ -f "$source/drivers/acpi/osl.c" ]] &&
     grep -Fq 'static struct osi_setup_entry __initdata' "$source/drivers/acpi/osl.c"; then
    needs_acpi_osi_initdata=1
  fi
  local realmode_makefile
  for realmode_makefile in "$source/arch/x86/boot/Makefile" "$source/arch/x86/realmode/Makefile" "$source/arch/x86/realmode/rm/Makefile" "$source/arch/x86/kernel/acpi/realmode/Makefile"; do
    if [[ -f "$realmode_makefile" ]] && grep -Fq -- '-fomit-frame-pointer' "$realmode_makefile" && ! grep -Fq -- '-fno-pic' "$realmode_makefile"; then
      needs_realmode_no_pic=1
    fi
  done
  if [[ "$version" == v5.10 ]] &&
     grep -Fq 'select HAVE_STATIC_CALL_INLINE' "$source/arch/x86/Kconfig"; then
    needs_static_call_compat=1
  fi
  if [[ -f "$source/arch/x86_64/kernel/process.c" ]] &&
     grep -Fq 'movl %%gs' "$source/arch/x86_64/kernel/process.c"; then
    needs_x86_segment_mov=1
  fi
  # GNU as rejects the historical copy routine's cross-section .size
  # expression. Function size metadata is optional; ENTRY already records the
  # symbol type and the exception table remains unchanged.
  local copy_user_source=""
  for copy_user_source in "$source/arch/x86_64/lib/copy_user.S" "$source/arch/x86/lib/copy_user_64.S"; do
    if [[ -f "$copy_user_source" ]] && grep -Fq 'END(copy_user_generic_c)' "$copy_user_source"; then
      needs_copy_user_size=1
      break
    fi
  done
  # Linux 3.x/4.x decompressor Makefiles replace the normal kernel
  # CFLAGS, so command-line KCFLAGS never reach their private memcpy/memset.
  # Modern GCC can turn those routines into REP string instructions before
  # setup has established usable segment state, causing a pre-console fault.
  # Linux 3.x/4.x use the sealed GCC 4.9 toolchain below, so their
  # historical decompressor flags and copy routines remain unchanged.
  # Some pre-4.x x86_64 entry paths tear down the identity mapping before
  # copying boot parameters. Map only those two input buffers explicitly;
  # retain the kernel's original page-table reset and direct-map setup.
  if [[ "$version" =~ ^v3\.([2-9]|1[0-9])$ || "$version" == v4.0 ]] &&
     [[ -f "$source/arch/x86/kernel/head64.c" ]] &&
     grep -Fq 'copy_bootdata(__va(real_mode_data));' "$source/arch/x86/kernel/head64.c"; then
    needs_bootdata_mapping=1
  fi
  # Before z_run_size relocation, a sufficiently large compressed kernel can
  # execute parse_elf from an address that a PT_LOAD copy is about to replace.
  # Keep the running decompressor beyond the complete expanded image.
  if [[ -f "$source/arch/x86/boot/compressed/mkpiggy.c" ]] &&
     ! grep -Fq 'z_run_size' "$source/arch/x86/boot/compressed/mkpiggy.c"; then
    needs_extract_overlap=1
  fi
  if [[ -f "$source/include/linux/compiler-gcc.h" ]] &&
     grep -Fq '#include gcc_header(__GNUC__)' "$source/include/linux/compiler-gcc.h" &&
     [[ ! -f "$source/include/linux/compiler-gcc$(gcc -dumpversion | cut -d. -f1).h" ]]; then
    needs_gcc_header_fallback=1
  fi
  if (( needs_make4 == 0 && needs_e820 == 0 && needs_memmap_holes == 0 && needs_kconfig260 == 0 && needs_force_order == 0 && needs_plt32 == 0 && needs_percpu_reloc_static == 0 && needs_unlzo_header_static == 0 && needs_x86cpu_device_alias == 0 && needs_i915_inline_static == 0 && needs_acpi_osi_initdata == 0 && needs_realmode_no_pic == 0 && needs_static_call_compat == 0 && needs_gcc_header_fallback == 0 && needs_x86_segment_mov == 0 && needs_copy_user_size == 0 && needs_compressed_host_flags == 0 && needs_compressed_memcpy == 0 && needs_extract_overlap == 0 && needs_bootdata_mapping == 0 )); then printf '%s\n' "$source"; return; fi
  out="$KLAB_CACHE/compat-sources/${version#v}-compat-v65"
  if [[ ! -f "$out/.klab-legacy-compat" ]]; then
    mkdir -p "$(dirname "$out")"
    tmp="$out.tmp.$$"; [[ ! -e "$tmp" ]] || { chmod -R u+w "$tmp"; rm -rf "$tmp"; }; cp -a "$source" "$tmp"
    chmod -R u+w "$tmp"
    python3 - "$tmp/Makefile" "$version" <<'PYMAKE'
from pathlib import Path
import sys
p=Path(sys.argv[1]); version=sys.argv[2]; parts=[int(x) for x in version[1:].split('.')[:2]]; affected_x86_mapping=(parts[0] == 3 and 2 <= parts[1] <= 19) or parts == [4, 0]; affected_x86_elf=parts[0] == 3 and 11 <= parts[1] <= 19; affected_x86_overlap=parts[0] == 3 and 18 <= parts[1] <= 19; s=p.read_text()
s=s.replace('''config %config: scripts_basic outputmakefile FORCE
\t$(Q)mkdir -p include/linux include/config
\t$(Q)$(MAKE) $(build)=scripts/kconfig $@
''','''config: scripts_basic outputmakefile FORCE
\t$(Q)mkdir -p include/linux include/config
\t$(Q)$(MAKE) $(build)=scripts/kconfig $@
%config: scripts_basic outputmakefile FORCE
\t$(Q)mkdir -p include/linux include/config
\t$(Q)$(MAKE) $(build)=scripts/kconfig $@
''',1)
# Linux 2.6.14-2.6.18 use the same mixed implicit/normal rule with a
# shorter mkdir recipe. Split any remaining variant while preserving its
# prerequisites and complete recipe verbatim.
import re
s=re.sub(r'(?m)^config %config:([^\n]*)\n((?:\t[^\n]*\n)+)',
         lambda m: 'config:'+m.group(1)+'\n'+m.group(2)+'%config:'+m.group(1)+'\n'+m.group(2), s, count=1)
s=s.replace('''/ %/: prepare scripts FORCE
\t$(Q)$(MAKE) KBUILD_MODULES=$(if $(CONFIG_MODULES),1) \\
\t$(build)=$(build-dir)
''','''/: prepare scripts FORCE
\t$(Q)$(MAKE) KBUILD_MODULES=$(if $(CONFIG_MODULES),1) \\
\t$(build)=$(build-dir)
%/: prepare scripts FORCE
\t$(Q)$(MAKE) KBUILD_MODULES=$(if $(CONFIG_MODULES),1) \\
\t$(build)=$(build-dir)
''',1)
p.write_text(s)
m=p.parent/'kernel/mutex.c'
if m.exists():
    t=m.read_text()
    for old,new in (
        ('static void fastcall noinline __sched\n__mutex_lock_slowpath', 'static void fastcall noinline __attribute__((used)) __sched\n__mutex_lock_slowpath'),
        ('static void fastcall noinline __sched\n__mutex_unlock_slowpath', 'static void fastcall noinline __attribute__((used)) __sched\n__mutex_unlock_slowpath'),
        ('static fastcall noinline void\n__mutex_unlock_slowpath', 'static fastcall noinline __attribute__((used)) void\n__mutex_unlock_slowpath'),
        ('static void noinline __sched\n__mutex_lock_slowpath', 'static void noinline __attribute__((used)) __sched\n__mutex_lock_slowpath'),
        ('static noinline void __sched\n__mutex_lock_slowpath', 'static noinline void __attribute__((used)) __sched\n__mutex_lock_slowpath'),
        ('static noinline void __sched __mutex_unlock_slowpath', 'static noinline void __attribute__((used)) __sched __mutex_unlock_slowpath'),
        ('static noinline void\n__mutex_unlock_slowpath', 'static noinline void __attribute__((used))\n__mutex_unlock_slowpath'),
    ):
        t=t.replace(old,new)
    m.write_text(t)
k=p.parent/'scripts/kconfig/mconf.c'
if k.exists():
    t=k.read_text()
    t=t.replace('static struct menu *current_menu;', 'struct menu *current_menu;', 1)
    k.write_text(t)
proc=p.parent/'include/asm-x86_64/processor.h'
if proc.exists():
    t=proc.read_text()
    decl='extern struct tss_struct init_tss[NR_CPUS];\n'
    if decl in t and 'struct tss_struct { ' not in t:
        t=t.replace(decl, '', 1)
        marker='} __attribute__((packed)) ____cacheline_aligned;\n'
        if marker not in t: raise SystemExit('legacy TSS structure marker missing')
        t=t.replace(marker, marker+'\n'+decl, 1)
        proc.write_text(t)
proc32=p.parent/'include/asm-i386/processor.h'
if proc32.exists():
    t=proc32.read_text()
    decl='extern struct tss_struct init_tss[NR_CPUS];\nextern struct tss_struct doublefault_tss;\n'
    marker='} __attribute__((packed));\n'
    if decl in t:
        if marker not in t: raise SystemExit('legacy i386 TSS structure marker missing')
        t=t.replace(decl, '', 1).replace(marker, marker+'\n'+decl, 1)
        proc32.write_text(t)
copy_user=next((q for q in (p.parent/'arch/x86_64/lib/copy_user.S', p.parent/'arch/x86/lib/copy_user_64.S') if q.exists()), None)
if copy_user is not None:
    t=copy_user.read_text()
    marker='END(copy_user_generic_c)'
    if marker in t:
        t=t.replace(marker, '/* KLab: omit obsolete cross-section function size */', 1)
        copy_user.write_text(t)

process=p.parent/'arch/x86_64/kernel/process.c'
if process.exists():
    t=process.read_text()
    for seg in ('gs','fs','es','ds'):
        t=t.replace('movl %%'+seg+',%0\" : \"=m\" (p->thread.', 'mov %%'+seg+',%0\" : \"=m\" (p->thread.')
    t=t.replace('movl %%es,%0\" : \"=m\" (prev->es)', 'mov %%es,%0\" : \"=m\" (prev->es)')
    t=t.replace('movl %%ds,%0\" : \"=m\" (prev->ds)', 'mov %%ds,%0\" : \"=m\" (prev->ds)')
    process.write_text(t)
# Linux 2.6.28-2.6.36 pass GNU ld emulation flags through the GCC driver.
# Modern GCC requires those linker-only options behind -Wl,.
b2c2=p.parent/'drivers/media/dvb/b2c2/Makefile'
if b2c2.exists():
    t=b2c2.read_text().replace('$(CONFIG_DVB_B2C2_USB) + =', '$(CONFIG_DVB_B2C2_USB) +=')
    b2c2.write_text(t)
head64=p.parent/'arch/x86/kernel/head64.c'
if affected_x86_mapping and head64.exists():
    t=head64.read_text()
    reset='\t/* Kill off the identity-map trampoline */\n\treset_early_page_tables();\n\n'
    copy='\tcopy_bootdata(__va(real_mode_data));\n'
    marker='\t/* KLab: retain loader mappings until boot inputs are copied. */\n'
    if reset in t and copy in t and marker not in t:
        t=t.replace(reset, '', 1)
        decl='int __init early_make_pgtable(unsigned long address);\n'
        fn='static void __init copy_bootdata(char *real_mode_data)\n'
        if decl not in t: t=t.replace(fn, decl+'\n'+fn, 1)
        memcpy='\tmemcpy(&boot_params, real_mode_data, sizeof boot_params);\n'
        t=t.replace(memcpy, '\tearly_make_pgtable((unsigned long)real_mode_data);\n'+memcpy, 1)
        cmd='\t\tcommand_line = __va(cmd_line_ptr);\n'
        t=t.replace(cmd, '\t\tearly_make_pgtable((unsigned long)__va(cmd_line_ptr));\n'+cmd, 1)
        t=t.replace(copy, copy+'\n'+marker+'\treset_early_page_tables();\n\tearly_make_pgtable((unsigned long)__va(0));\n\tearly_make_pgtable((unsigned long)__va(read_cr3()));\n', 1)
        head64.write_text(t)

mm_init=p.parent/'arch/x86/mm/init.c'
if affected_x86_mapping and mm_init.exists():
    t=mm_init.read_text()
    alloc='\tbase = __pa(extend_brk(tables, PAGE_SIZE));\n'
    map_brk='\t/* KLab: make the early page-table BRK buffer writable. */\n\tearly_make_pgtable((unsigned long)__va(base));\n'
    if alloc in t and map_brk not in t:
        decl='int __init early_make_pgtable(unsigned long address);\n\n'
        anchor='static unsigned long __initdata pgt_buf_start;\n'
        if decl not in t: t=t.replace(anchor, decl+anchor, 1)
        t=t.replace(alloc, alloc+map_brk, 1)
        mm_init.write_text(t)

mkpiggy=p.parent/'arch/x86/boot/compressed/mkpiggy.c'
if mkpiggy.exists():
    t=mkpiggy.read_text()
    rounding='\toffs = (offs+4095) & ~4095; /* Round to a 4K boundary */\n'
    guard=('\t/* KLab: keep the running decompressor beyond the expanded image. */\n'
           '\tif (offs < olen)\n'
           '\t\toffs = (olen+4095) & ~4095;\n')
    if 'z_run_size' not in t and rounding in t and guard not in t:
        mkpiggy.write_text(t.replace(rounding, rounding+guard, 1))
    elif affected_x86_overlap and rounding in t and 'KLab: 8 MiB decompressor floor' not in t:
        floor=('\t/* KLab: 8 MiB decompressor floor avoids PT_LOAD self-overlap. */\n'
               '\tif (offs < 8*1024*1024)\n'
               '\t\toffs = 8*1024*1024;\n')
        mkpiggy.write_text(t.replace(rounding, rounding+floor, 1))
    misc=mkpiggy.parent/'misc.c'
    if misc.exists():
        u=misc.read_text()
        forward='\tfor (i = 0; i < ehdr.e_phnum; i++) {\n'
        reverse='\t/* KLab: preserve unread high ELF segments during in-place expansion. */\n\tfor (i = ehdr.e_phnum - 1; i >= 0; i--) {\n'
        if affected_x86_elf and forward in u and reverse not in u:
            misc.write_text(u.replace(forward, reverse, 1))

vdso=p.parent/'arch/x86/vdso/Makefile'
if vdso.exists():
    t=vdso.read_text()
    t=t.replace('-m elf_x86_64', '-Wl,-m,elf_x86_64')
    t=t.replace('-m elf_i386', '-Wl,-m,elf_i386')
    vdso.write_text(t)
vdso64=p.parent/'arch/x86_64/vdso/Makefile'
if vdso64.exists():
    t=vdso64.read_text()
    t=t.replace('$(CC) -m elf_x86_64', '$(CC) -Wl,-m,elf_x86_64')
    vdso64.write_text(t)
calling=p.parent/'include/asm-x86_64/calling.h'
if calling.exists():
    t=calling.read_text()
    block='''\n\t/* push in order ss, rsp, eflags, cs, rip */
\t.macro FAKE_STACK_FRAME child_rip
\txorl %eax,%eax
\tsubq $6*8,%rsp
\tmovq %rax,5*8(%rsp)  /* ss */
\tmovq %rax,4*8(%rsp)  /* rsp */
\tmovq $(1<<9),3*8(%rsp)  /* eflags */
\tmovq $__KERNEL_CS,2*8(%rsp) /* cs */
\tmovq \child_rip,1*8(%rsp)  /* rip */
\tmovq %rax,(%rsp)   /* orig_rax */
\t.endm

\t.macro UNFAKE_STACK_FRAME
\taddq $8*6, %rsp
\t.endm
'''
    if block in t:
        t=t.replace(block, '\n', 1)
        calling.write_text(t)
bootmake=p.parent/'arch/x86_64/boot/Makefile'
if bootmake.exists():
    t=bootmake.read_text()
    anchor='host-progs\t:= tools/build\n'
    if anchor in t and 'HOST_EXTRACFLAGS += $(LINUXINCLUDE)' not in t:
        t=t.replace(anchor, anchor+'HOST_EXTRACFLAGS += -Iinclude2 -I$(srctree)/include\n', 1)
        bootmake.write_text(t)
for buildtool in (p.parent/'arch/x86_64/boot/tools/build.c', p.parent/'arch/i386/boot/tools/build.c'):
    if buildtool.exists():
        t=buildtool.read_text()
        anchor='#include <asm/boot.h>\n'
        fallback='#ifndef DEF_SYSSIZE\n#define DEF_SYSSIZE 0x7F00\n#endif\n'
        if anchor in t and fallback not in t:
            t=t.replace(anchor, anchor+fallback, 1)
            buildtool.write_text(t)
compressed=p.parent/'arch/x86/boot/compressed'
definition='unsigned long __force_order;'
force_defs=[]
if compressed.is_dir():
    force_defs=[f for f in sorted(compressed.glob('*.c')) if definition in f.read_text()]
if len(force_defs) > 1:
    keeper=compressed/'pgtable_64.c'
    if keeper not in force_defs:
        keeper=force_defs[0]
    for f in force_defs:
        if f != keeper:
            t=f.read_text()
            f.write_text(t.replace(definition, 'extern unsigned long __force_order;', 1))

relocs=p.parent/'arch/x86/tools/relocs.c'
if relocs.exists():
    t=relocs.read_text()
    pc32='\tcase R_X86_64_PC32:\n'
    plt32='\tcase R_X86_64_PLT32:\n'
    if pc32 in t and plt32 not in t:
        t=t.replace(pc32, pc32+plt32, 1)
    tentative='Elf_Addr per_cpu_load_addr;'
    static='static Elf_Addr per_cpu_load_addr;'
    if tentative in t and static not in t:
        t=t.replace(tentative, static, 1)
    relocs.write_text(t)

module_reloc=p.parent/'arch/x86/kernel/module.c'
if module_reloc.exists():
    t=module_reloc.read_text()
    pc32='\t\tcase R_X86_64_PC32:\n'
    plt32='\t\tcase R_X86_64_PLT32:\n'
    if pc32 in t and plt32 not in t:
        module_reloc.write_text(t.replace(pc32, pc32+plt32, 1))

unlzo=p.parent/'lib/decompress_unlzo.c'
if unlzo.exists():
    t=unlzo.read_text()
    for declaration in ('STATIC inline int INIT parse_header', 'STATIC inline long INIT parse_header'):
        if declaration in t:
            t=t.replace(declaration, declaration.replace('STATIC', 'static'), 1)
    unlzo.write_text(t)

mod_devicetable=p.parent/'include/linux/mod_devicetable.h'
if mod_devicetable.exists():
    t=mod_devicetable.read_text()
    declaration='struct x86_cpu_id {'
    alias='#define x86cpu_device_id x86_cpu_id\n'
    if declaration in t and alias not in t:
        t=t.replace(declaration, alias+declaration, 1)
    mod_devicetable.write_text(t)

i915_drv=p.parent/'drivers/gpu/drm/i915/i915_drv.h'
if i915_drv.exists():
    t=i915_drv.read_text()
    for helper in ('intel_gmbus_is_port_valid', 'intel_gmbus_is_forced_bit'):
        declaration='extern inline bool '+helper
        if declaration in t:
            t=t.replace(declaration, 'static inline bool '+helper, 1)
    i915_drv.write_text(t)

acpi_osl=p.parent/'drivers/acpi/osl.c'
if acpi_osl.exists():
    t=acpi_osl.read_text()
    old='static struct osi_setup_entry __initdata\n\t\tosi_setup_entries[OSI_STRING_ENTRIES_MAX] = {'
    new='static struct osi_setup_entry\n\t\tosi_setup_entries[OSI_STRING_ENTRIES_MAX] = {'
    if old in t:
        t=t.replace(old, new, 1)
    inline='static struct osi_setup_entry __initdata osi_setup_entries'
    if inline in t:
        t=t.replace(inline, 'static struct osi_setup_entry osi_setup_entries', 1)
    acpi_osl.write_text(t)

for realmode_make in (p.parent/'arch/x86/boot/Makefile', p.parent/'arch/x86/realmode/Makefile', p.parent/'arch/x86/realmode/rm/Makefile', p.parent/'arch/x86/kernel/acpi/realmode/Makefile'):
    if realmode_make.exists():
        t=realmode_make.read_text()
        flags='-fno-strict-aliasing -fomit-frame-pointer'
        if flags in t and '-fno-pic' not in t:
            t=t.replace(flags, flags+' -fno-pic', 1)
        realmode_make.write_text(t)

x86kconfig=p.parent/'arch/x86/Kconfig'
if x86kconfig.exists():
    t=x86kconfig.read_text()
    inline_select='\tselect HAVE_STATIC_CALL_INLINE\t\tif HAVE_STACK_VALIDATION\n'
    if inline_select in t:
        x86kconfig.write_text(t.replace(inline_select, '', 1))

compiler_gcc=p.parent/'include/linux/compiler-gcc.h'
if compiler_gcc.exists():
    t=compiler_gcc.read_text()
    dispatch='#include gcc_header(__GNUC__)'
    numbered=sorted(compiler_gcc.parent.glob('compiler-gcc[0-9]*.h'), key=lambda f: int(f.stem.removeprefix('compiler-gcc')))
    if dispatch in t and numbered:
        newest=int(numbered[-1].stem.removeprefix('compiler-gcc'))
        fallback=f'#if __GNUC__ > {newest}\n#include <linux/compiler-gcc{newest}.h>\n#else\n{dispatch}\n#endif'
        compiler_gcc.write_text(t.replace(dispatch, fallback, 1))

mainc=p.parent/'init/main.c'
if mainc.exists():
    t=mainc.read_text()
    decl='extern void prepare_namespace(void);\n'
    if decl in t and 'KLab early rootfs init compatibility' not in t:
        t=t.replace(decl, decl+'extern asmlinkage long sys_access(const char __user * filename, int mode);\n', 1)
        call='\tprepare_namespace();\n'
        body='''\t/* KLab early rootfs init compatibility: Linux 2.6.0 always
\t * attempted to mount a block root even when populate_rootfs supplied /init. */
\tif (sys_access((const char __user *) "/init", 0) == 0)
\t\texecute_command = "/init";
\telse
\t\tprepare_namespace();
'''
        if call not in t: raise SystemExit('prepare_namespace call missing')
        t=t.replace(call, body, 1)
        mainc.write_text(t)
PYMAKE
    [[ $? -eq 0 ]] || die "failed to adapt legacy Makefile for GNU Make 4"
    if (( needs_e820 == 1 )); then
      patch -s -d "$tmp" -p1 --forward --batch < "$SELF_DIR/legacy/patches/linux-2.6.12-e820-holes.patch" || die "failed to apply Linux 2.6.12 E820-hole compatibility patch"
    fi
    if (( needs_memmap_holes == 1 )); then
      python3 - "$tmp/arch/x86_64/mm/init.c" <<'PYMEMMAP'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
decl="\t\tunsigned int max_dma;\n"
call="\t\tfree_area_init_node(0, NODE_DATA(0), zones_size,\n"
if decl not in s or call not in s:
    raise SystemExit('early x86_64 zone layout marker missing')
s=s.replace(decl, decl+"\t\tint i;\n", 1)
zone=("\t\t/* Linux 2.6.15 accounts mem_map storage as zone holes. */\n"
      "\t\tfor (i = 0; i < MAX_NR_ZONES; i++)\n"
      "\t\t\tholes[i] += (zones_size[i] * sizeof(struct page)) / PAGE_SIZE;\n")
s=s.replace(call, zone+call, 1)
marker="extern char _stext[];\n"
if marker not in s:
    raise SystemExit('dma_reserve declaration marker missing')
s=s.replace(marker, marker+"static unsigned long dma_reserve __initdata;\n", 1)
reserve="\treserve_bootmem(phys, len);    \n#endif\n}"
if reserve not in s:
    raise SystemExit('reserve_bootmem_generic marker missing')
s=s.replace(reserve, "\treserve_bootmem(phys, len);    \n#endif\n\tif (phys+len <= virt_to_phys((char *)MAX_DMA_ADDRESS))\n\t\tdma_reserve += len / PAGE_SIZE;\n}", 1)
dma=(zone+"\t\tif (holes[ZONE_DMA]) {\n"
          "\t\t\tholes[ZONE_DMA] += dma_reserve;\n"
          "\t\t\tif (holes[ZONE_DMA] >= zones_size[ZONE_DMA])\n"
          "\t\t\t\tholes[ZONE_DMA] = zones_size[ZONE_DMA];\n"
          "\t\t}\n")
if zone not in s:
    raise SystemExit('mem_map zone accounting marker missing')
s=s.replace(zone, dma, 1)
p.write_text(s)
PYMEMMAP
    fi
    cat > "$tmp/.klab-legacy-compat" <<EOF
schema=klab-legacy-source-compat-v65
upstream_version=$version
upstream_source=$source
make4_rules=$needs_make4
e820_holes_backport=$needs_e820
memmap_zone_holes=$needs_memmap_holes
dma_zone_reserve=$needs_memmap_holes
kconfig_current_menu_linkage=$needs_kconfig260
force_order_single_definition=$needs_force_order
plt32_relocation_compat=$needs_plt32
percpu_reloc_static=$needs_percpu_reloc_static
unlzo_header_static=$needs_unlzo_header_static
x86cpu_device_alias=$needs_x86cpu_device_alias
i915_inline_static=$needs_i915_inline_static
extract_offset_overlap_guard=$needs_extract_overlap
bootdata_copy_before_mapping_reset=$needs_bootdata_mapping
acpi_osi_initdata_resident_fallback=$needs_acpi_osi_initdata
realmode_no_pic=$needs_realmode_no_pic
static_call_inline_fallback=$needs_static_call_compat
gcc_header_fallback=$needs_gcc_header_fallback
x86_segment_mov_compat=$needs_x86_segment_mov
transformation=derived source for modern build host and QEMU PC E820 map
EOF
    if [[ -e "$out" ]]; then chmod -R u+w "$out"; rm -rf "$out"; fi
    mv "$tmp" "$out"
  fi
  printf '%s\n' "$out"
}

configure_kernel() {
  local source="$1" build="$2" profile="$3" arch="$(canonical_arch "${4:-$ARCH}")" config="$build/.config"
  say "Configuring profile '$profile' for $arch"
  mkdir -p "$build"
  # Early O= Kbuild assumes dependency and generated-firmware directories
  # already exist. GNU make 4 exposes the missing order-only prerequisites.
  mkdir -p "$build/scripts"
  if [[ -d "$source/firmware" ]]; then
    while IFS= read -r firmware_dir; do mkdir -p "$build/$firmware_dir"; done < <(cd "$source" && find firmware -type d -print)
  fi
  setup_upstream_build_toolchain "$arch" "$source"

  if [[ ! -f "$config" ]]; then
    local defcfg source_version source_patch legacy_seed=""
    defcfg="$(linux_defconfig_for_source "$arch" "$source")"
    source_version="$(sed -n 's/^VERSION[[:space:]]*=[[:space:]]*//p' "$source/Makefile" | head -n1)"
    source_patch="$(sed -n 's/^PATCHLEVEL[[:space:]]*=[[:space:]]*//p' "$source/Makefile" | head -n1)"
    if [[ "$source_version" == 2 && "$source_patch" =~ ^[0-9]+$ ]] && (( source_patch < 6 )) && [[ -f "$source/arch/$(linux_karch_for_source "$arch" "$source")/defconfig" ]]; then
      legacy_seed="$source/arch/$(linux_karch_for_source "$arch" "$source")/defconfig"
      cp "$legacy_seed" "$config"
      say "Seeded pre-2.6 configuration from ${legacy_seed#"$source"/}"
    elif ! upstream_make -s -C "$source" O="$build" "$defcfg"; then
      if [[ "$arch" == armv7 && "$defcfg" == multi_v7_defconfig ]]; then
        say "multi_v7_defconfig is unavailable in this older tree; falling back to vexpress_defconfig"
        upstream_make -s -C "$source" O="$build" vexpress_defconfig
      else
        die "kernel defconfig '$defcfg' failed for $arch"
      fi
    fi
  fi

  local opt
  for opt in \
      MODULES MODULE_UNLOAD BLK_DEV_INITRD RD_GZIP BINFMT_ELF BINFMT_SCRIPT \
      DEVTMPFS DEVTMPFS_MOUNT PROC_FS PROC_SYSCTL SYSFS TMPFS \
      TTY PRINTK DEBUG_KERNEL MAGIC_SYSRQ; do
    config_enable "$source" "$config" "CONFIG_$opt"
  done
  local arch_enable="" arch_disable=""
  arch_enable="$(arch_profile_field "$arch" KERNEL_CONFIG_ENABLE 2>/dev/null || true)"
  arch_disable="$(arch_profile_field "$arch" KERNEL_CONFIG_DISABLE 2>/dev/null || true)"
  if [[ -n "$arch_enable" ]]; then
    for opt in $arch_enable; do config_enable "$source" "$config" "CONFIG_$opt"; done
  else
    case "$arch" in
      x86_64|i386) for opt in SERIAL_8250 SERIAL_8250_CONSOLE PCI ACPI; do config_enable "$source" "$config" "CONFIG_$opt"; done ;;
      aarch64|armv7) for opt in SERIAL_AMBA_PL011 SERIAL_AMBA_PL011_CONSOLE PCI VIRTIO VIRTIO_MMIO VIRTIO_PCI PCI_HOST_GENERIC; do config_enable "$source" "$config" "CONFIG_$opt"; done ;;
    esac
  fi
  for opt in $arch_disable; do config_disable "$source" "$config" "CONFIG_$opt"; done

  config_disable "$source" "$config" CONFIG_MODULE_SIG_FORCE
  config_disable "$source" "$config" CONFIG_DEBUG_INFO_BTF
  # Linux 2.2's optional IDE-CD driver contains a declaration accepted by
  # its contemporary compiler but rejected by the sealed GCC 3.3 toolchain.
  # KLab boots its ext2 initrd directly and does not need ATAPI CD support.
  local configured_version configured_patch
  configured_version="$(sed -n 's/^VERSION[[:space:]]*=[[:space:]]*//p' "$source/Makefile" | head -n1)"
  configured_patch="$(sed -n 's/^PATCHLEVEL[[:space:]]*=[[:space:]]*//p' "$source/Makefile" | head -n1)"

  # Older x86 objtool releases cannot reliably parse objects emitted by
  # current host compilers. ORC and retpoline both select stack validation,
  # so disabling STACK_VALIDATION alone is undone by olddefconfig. Use the
  # supported frame-pointer unwinder and turn off both selectors. Their
  # SELinux headers also compare the host's newer AF_MAX with the historical
  # kernel value while building generated policy tables.
  # Linux 3.x/4.x are compiled with the sealed GCC 4.9 toolchain, whose
  # kernel code-generation defaults predate PIE and stack-protector defaults.
  # Preserve sealed-toolchain kernel flags. Host GCC is PIE-by-default, so
  # Linux 3.x needs only the code-generation defaults it did not yet carry.
  # Compatibility guests do not load physical CPU microcode. The Linux 3.x
  # early vendor loader can consume firmware pointers before its legacy direct
  # mapping is stable under modern QEMU, so keep this hardware-only path off.
  if [[ "$arch" =~ ^(x86_64|i386)$ && "$configured_version" =~ ^(3|4)$ ]]; then
    for opt in MICROCODE MICROCODE_INTEL MICROCODE_AMD; do
      config_disable "$source" "$config" "CONFIG_$opt"
    done
  fi

  if [[ "$arch" =~ ^(x86_64|i386)$ && "$configured_version" == 3 ]] &&
     ! grep -Eq -- '-fno-(PIE|pie)' "$source/Makefile"; then
    KLAB_BUILD_MAKE_ARGS+=("KCFLAGS=-fno-pie -fno-stack-protector" "KAFLAGS=-fno-pie")
  fi

  if [[ "$arch" =~ ^(x86_64|i386)$ ]] &&
     { [[ "$configured_version" == 4 ]] ||
       { [[ "$configured_version" == 5 && "$configured_patch" =~ ^[0-9]+$ ]] && (( configured_patch <= 10 )); }; }; then
    config_disable "$source" "$config" CONFIG_SECURITY_SELINUX
    config_disable "$source" "$config" CONFIG_RETPOLINE
    config_disable "$source" "$config" CONFIG_UNWINDER_ORC
    config_disable "$source" "$config" CONFIG_STACK_VALIDATION
    config_enable "$source" "$config" CONFIG_UNWINDER_FRAME_POINTER
  fi
  if [[ "$configured_version" == 2 && "$configured_patch" =~ ^(0|2)$ ]]; then
    config_disable "$source" "$config" CONFIG_BLK_DEV_IDECD
    config_disable "$source" "$config" CONFIG_NFS_FS
    config_disable "$source" "$config" CONFIG_SMP
    [[ "$configured_patch" != 0 ]] || config_disable "$source" "$config" CONFIG_BLK_DEV_FD
    # The sealed legacy SSH root is larger than the historical 4 MiB default.
    config_value "$source" "$config" CONFIG_BLK_DEV_RAM_SIZE 32768
    if [[ "$configured_patch" == 2 ]]; then
      for opt in NETDEVICES NET_ETHERNET EEXPRESS_PRO100 NE2K_PCI; do config_enable "$source" "$config" "CONFIG_$opt"; done
    else
      # QEMU exposes the ISA NE2000 at the historical defaults (0x300, IRQ 9).
      for opt in NETDEVICES NET_ETHERNET NET_ISA NE2000; do config_enable "$source" "$config" "CONFIG_$opt"; done
    fi
  fi
  config_string "$source" "$config" CONFIG_SYSTEM_TRUSTED_KEYS ""
  config_string "$source" "$config" CONFIG_SYSTEM_REVOCATION_KEYS ""

  for opt in KASAN KASAN_GENERIC KCSAN PROVE_LOCKING LOCKDEP DEBUG_LOCK_ALLOC DEBUG_ATOMIC_SLEEP; do
    config_disable "$source" "$config" "CONFIG_$opt"
  done

  # Early x86_64 2.6 NUMA setup is sensitive to QEMU PC E820 holes and
  # can BUG in free_pages_bulk() before init. The compatibility profile does
  # not exercise NUMA, so use the supported flat single-node model throughout
  # the historical 2.6 API-boundary sweep.
  # Use the supported flat single-node model for those historical targets.
  local legacy_version legacy_patch legacy_sublevel
  legacy_version="$(sed -n 's/^VERSION[[:space:]]*=[[:space:]]*//p' "$source/Makefile" | head -n1)"
  legacy_patch="$(sed -n 's/^PATCHLEVEL[[:space:]]*=[[:space:]]*//p' "$source/Makefile" | head -n1)"
  legacy_sublevel="$(sed -n 's/^SUBLEVEL[[:space:]]*=[[:space:]]*//p' "$source/Makefile" | head -n1)"
  if [[ "$arch" == x86_64 && "$legacy_version" == 2 && "$legacy_patch" == 6 ]]; then
    for opt in K8_NUMA NUMA_EMU NUMA DISCONTIGMEM; do config_disable "$source" "$config" "CONFIG_$opt"; done
    if [[ "$legacy_sublevel" =~ ^[0-9]+$ ]] && (( legacy_sublevel >= 31 && legacy_sublevel <= 34 )); then
      config_enable "$source" "$config" CONFIG_SMP
      config_value "$source" "$config" CONFIG_NR_CPUS 2
    else
      config_disable "$source" "$config" CONFIG_SMP
    fi
    # The direct initrd boot does not use an emulated ATAPI device. Several
    # early 2.6 IDE-CD drivers lose the QEMU interrupt while probing an empty
    # drive and can delay boot indefinitely.
    config_disable "$source" "$config" CONFIG_BLK_DEV_IDECD
    # Early x86_64 MMCONFIG support is optional on the legacy PC machine and
    # some historical trees cannot build it out-of-tree (their private PCI
    # header was not carried into arch/x86_64). Type-1 PCI configuration is
    # sufficient for KLab compatibility hardware.
    config_disable "$source" "$config" CONFIG_PCI_MMCONFIG
  fi
  # Preserve the stock decompressor/load geometry for 3.18-3.19. Their
  # defconfigs enable enough unused built-in subsystems to overlap the running
  # decompressor under QEMU's legacy x86 boot protocol, so trim facilities
  # outside KLab's serial, initramfs, module, IPv4, and e1000 gate.
  if [[ "$arch" == x86_64 && "$configured_version" == 3 && "$configured_patch" =~ ^(18|19)$ ]]; then
    for opt in NETFILTER IPV6 WIRELESS CFG80211 MAC80211 HAMRADIO DRM SOUND SND MEDIA_SUPPORT USB_SUPPORT USB SCSI ATA PCCARD EXT4_FS NFS_FS NFSD CIFS XFS_FS BTRFS_FS REISERFS_FS JFS_FS FUSE_FS AUTOFS4_FS SECURITY_SELINUX SECURITY_SMACK SECURITY_TOMOYO SECURITY_APPARMOR FTRACE TRACING BLK_DEV_MD MD INPUT HID ACPI PROFILING PERF_EVENTS KPROBES NET_VENDOR_3COM NET_VENDOR_ADAPTEC NET_VENDOR_AGERE NET_VENDOR_ALTEON NET_VENDOR_AMD NET_VENDOR_ARC NET_VENDOR_ATHEROS NET_VENDOR_BROADCOM NET_VENDOR_BROCADE NET_VENDOR_CHELSIO NET_VENDOR_CISCO NET_VENDOR_DEC NET_VENDOR_DLINK NET_VENDOR_EMULEX NET_VENDOR_EXAR NET_VENDOR_HP NET_VENDOR_I825XX NET_VENDOR_MARVELL NET_VENDOR_MELLANOX NET_VENDOR_MICREL NET_VENDOR_MYRI NET_VENDOR_NATSEMI NET_VENDOR_8390 NET_VENDOR_NVIDIA NET_VENDOR_OKI NET_VENDOR_QLOGIC NET_VENDOR_QUALCOMM NET_VENDOR_REALTEK NET_VENDOR_RDC NET_VENDOR_SAMSUNG NET_VENDOR_SEEQ NET_VENDOR_SILAN NET_VENDOR_SIS NET_VENDOR_SMSC NET_VENDOR_STMICRO NET_VENDOR_SUN NET_VENDOR_TEHUTI NET_VENDOR_TI NET_VENDOR_VIA NET_VENDOR_WIZNET; do
      config_disable "$source" "$config" "CONFIG_$opt"
    done
    config_enable "$source" "$config" CONFIG_CC_OPTIMIZE_FOR_SIZE
  fi
  # Linux 2.4 delegates symbol version generation to a host-installed
  # module-init-tools genksyms. The portable legacy gate does not require
  # modversions, so keep module support while removing that host dependency.
  if [[ "$legacy_version" == 2 && "$legacy_patch" =~ ^[0-9]+$ ]] && (( legacy_patch < 6 )); then
    config_disable "$source" "$config" CONFIG_MODVERSIONS
    for opt in SERIAL SERIAL_CONSOLE BLK_DEV_RAM BLK_DEV_INITRD; do config_enable "$source" "$config" "CONFIG_$opt"; done
  fi

  case "$profile" in
    normal) ;;
    debug)
      config_enable "$source" "$config" CONFIG_DEBUG_ATOMIC_SLEEP
      config_enable "$source" "$config" CONFIG_DEBUG_LOCK_ALLOC
      ;;
    kasan)
      config_enable "$source" "$config" CONFIG_KASAN
      config_enable "$source" "$config" CONFIG_KASAN_GENERIC
      ;;
    kcsan) config_enable "$source" "$config" CONFIG_KCSAN ;;
    lockdep)
      config_enable "$source" "$config" CONFIG_LOCKDEP
      config_enable "$source" "$config" CONFIG_PROVE_LOCKING
      config_enable "$source" "$config" CONFIG_DEBUG_LOCK_ALLOC
      ;;
    *) die "unknown profile '$profile'" ;;
  esac

  if ! upstream_make -s -C "$source" O="$build" olddefconfig; then
    say "olddefconfig is unavailable or failed; trying legacy non-interactive oldconfig"
    set +e
    yes '' | upstream_make -s -C "$source" O="$build" oldconfig
    local oldconfig_rc=${PIPESTATUS[1]}
    set -e
    (( oldconfig_rc == 0 )) || die "kernel configuration update failed with both olddefconfig and oldconfig"
  fi
}

prepare_build() {
  local raw="$1" profile="${2:-normal}" arch="$(canonical_arch "${3:-$ARCH}")"
  local version commit key build source image_rel build_jobs="$JOBS"
  version="$(normalize_version "$raw")"
  commit="$(fetch_ref_commit "$version")"
  source="$(materialize_source "$version" "$commit")"
  source="$(prepare_legacy_make_compat_source "$source" "$version")"
  key="$(build_key "$version" "$profile" "$commit" "$arch")"
  build="$BUILDS/$key"

  # Linux before 2.6 has no KBUILD_OUTPUT/O= support. Build a private writable
  # source copy inside work/builds while leaving the checksummed cache source
  # immutable and reusable.
  local source_version source_patch pristine_source="$source"
  source_version="$(sed -n 's/^VERSION[[:space:]]*=[[:space:]]*//p' "$source/Makefile" | head -n1)"
  source_patch="$(sed -n 's/^PATCHLEVEL[[:space:]]*=[[:space:]]*//p' "$source/Makefile" | head -n1)"
  if [[ "$source_version" == 2 && "$source_patch" =~ ^[0-9]+$ ]] && (( source_patch < 6 )); then
    if [[ ! -f "$build/.klab-in-tree-commit" || "$(cat "$build/.klab-in-tree-commit" 2>/dev/null || true)" != "$commit" ]]; then
      [[ ! -e "$build" ]] || { chmod -R u+w "$build"; rm -rf "$build"; }
      mkdir -p "$build"
      cp -a "$pristine_source/." "$build/"
      chmod -R u+w "$build"
      # Linux 2.4's image builder names a host unsigned long `u32`; make the
      # on-disk field width explicit when the host itself is 64-bit.
      if [[ -f "$build/arch/i386/boot/tools/build.c" ]]; then
        sed -i 's/^typedef unsigned long u32;$/typedef unsigned int u32;/' "$build/arch/i386/boot/tools/build.c"
      fi
      printf '%s\n' "$commit" > "$build/.klab-in-tree-commit"
    fi
    if [[ "$version" == v2.0.40 ]] && ! patch -s -R --dry-run -d "$build" -p1 < "$SELF_DIR/legacy/patches/linux-2.0.40-modern-host.patch"; then
      patch -s -d "$build" -p1 < "$SELF_DIR/legacy/patches/linux-2.0.40-modern-host.patch" || die "failed to apply Linux 2.0 modern-host compatibility patch"
    fi
    if [[ "$version" == v2.2.26 ]] && ! patch -s -R --dry-run -d "$build" -p1 < "$SELF_DIR/legacy/patches/linux-2.2.26-memscan-string.patch"; then
      patch -s -d "$build" -p1 < "$SELF_DIR/legacy/patches/linux-2.2.26-memscan-string.patch" || die "failed to apply Linux 2.2 GCC string compatibility patch"
    fi
    source="$build"
  fi

  configure_kernel "$source" "$build" "$profile" "$arch"
  # configure_kernel initialized the architecture-specific toolchain state.
  say "Building kernel $version ($arch/$profile) from immutable source $(basename "$source")"
  if [[ "$version" =~ ^v2\.6\.([0-9]+)$ ]] && (( 10#${BASH_REMATCH[1]} <= 11 )); then
    # Early O= Kbuild races multiple host-tool recipes against the same .d
    # file. Contemporary make happened to serialize these; make 4 does not.
    build_jobs=1
  fi
  if [[ "$source_version" == 2 && "$source_patch" =~ ^[0-9]+$ ]] && (( source_patch < 6 )); then
    # Pre-2.6 kbuild requires an explicit dependency pass and boot-image
    # target; its default target stops after generating .depend on a new tree.
    build_jobs=1
    upstream_make -C "$source" clean
    upstream_make -C "$source" dep
    upstream_make -C "$source" -j"$build_jobs" bzImage
  else
    upstream_make -C "$source" O="$build" -j"$build_jobs"
  fi
  record_upstream_compiler "$build"

  printf '%s\n' "$commit" > "$build/.klab-commit"
  printf '%s\n' "$source" > "$build/.klab-source-dir"
  printf '%s\n' "$arch" > "$build/.klab-arch"
  printf '%s\n' "$(linux_karch_for_source "$arch" "$source")" > "$build/.klab-karch"
  image_rel="$(linux_kernel_image_rel_for_source "$arch" "$source")"
  printf '%s\n' "$image_rel" > "$build/.klab-image-rel"
  [[ -f "$build/$image_rel" ]] || die "kernel build did not produce $image_rel"
  [[ -f "$build/Module.symvers" ]] || say "Warning: no Module.symvers was produced"

  # QEMU's direct Linux loader does not implement these early boot protocols.
  # Package a GRUB linux16 ISO with a syscall-only init beside each kernel.
  if [[ "$arch" == i386 && ( "$version" == v2.0.40 || "$version" == v2.2.26 ) ]]; then
    make_legacy_linux16_boot_iso "$build" "$build/$image_rel" "$version"
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' "$version" "$commit" "$key" "$arch" "$build"
}

external_module_make_assignment() {
  local source="$1" module_dir="$2"
  if grep -q "KBUILD_EXTMOD" "$source/Makefile"; then
    printf "M=%s\n" "$module_dir"
  else
    # Early 2.6 kbuild documents SUBDIRS=$PWD for external modules. Passing
    # the later M= spelling is ignored and a `clean` target wipes the kernel.
    printf "SUBDIRS=%s\n" "$module_dir"
  fi
}

build_external_module() {
  local build="$1" module_dir="$2" source arch karch
  module_dir="$(readlink -f "$module_dir")"
  [[ -d "$module_dir" ]] || die "module directory does not exist: $module_dir"
  [[ -f "$module_dir/Makefile" || -f "$module_dir/Kbuild" ]] || die "module directory needs a Makefile or Kbuild"
  source="$(source_for_cached_build "$build")"
  arch="$(cat "$build/.klab-arch" 2>/dev/null || echo x86_64)"; arch="$(canonical_arch "$arch")"; karch="$(linux_karch_for_build "$build" "$arch")"

  say "Building external module(s) against $(basename "$build") [$arch]"
  prepare_cached_upstream_toolchain "$build"
  local ext_assignment
  ext_assignment="$(external_module_make_assignment "$source" "$module_dir")"
  if [[ "$ext_assignment" == M=* ]]; then
    PATH="$KLAB_TC_PATH" LD_LIBRARY_PATH="${KLAB_TC_LIBRARY_PATH:-${LD_LIBRARY_PATH:-}}" make "${KLAB_TC_MAKE_ARGS[@]}" ARCH="$karch" -s -C "$source" O="$build" "$ext_assignment" clean || true
  fi
  PATH="$KLAB_TC_PATH" LD_LIBRARY_PATH="${KLAB_TC_LIBRARY_PATH:-${LD_LIBRARY_PATH:-}}" make "${KLAB_TC_MAKE_ARGS[@]}" ARCH="$karch" -C "$source" O="$build" "$ext_assignment" -j"$JOBS" modules

  mapfile -t MODULE_FILES < <(find "$module_dir" -maxdepth 3 -type f -name '*.ko' -print | sort)
  ((${#MODULE_FILES[@]} > 0)) || die "no .ko files were produced under $module_dir"
}

make_initramfs() {
  local key="$1" test_script="$2"
  shift 2
  local root="$INITRAMFS/$key.root" image="$INITRAMFS/$key.cpio.gz" mod
  test_script="$(readlink -f "$test_script")"
  [[ -f "$test_script" ]] || die "guest test script not found: $test_script"

  # A prior native userspace may contain read-only directories and files.
  # Make the disposable tree writable before replacing it for another mode.
  if [[ -d "$root" ]]; then chmod -R u+w "$root" 2>/dev/null || true; fi
  rm -rf "$root"
  mkdir -p "$root"
  populate_guest_root "$root" "$ACTIVE_USERSPACE_SPEC" "$ARCH"
  mkdir -p "$root/test/modules"
  cp "$test_script" "$root/test/test.sh"
  chmod +x "$root/test/test.sh"

  for mod in "$@"; do
    cp "$mod" "$root/test/modules/"
  done

  cat > "$root/init" <<'EOINIT'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

echo "KLAB_GUEST_BEGIN kernel=$(uname -r)"
echo "KLAB_PROC_VERSION=$(cat /proc/version)"
rc=0
for m in /test/modules/*.ko /test/modules/*.o; do
    [ -e "$m" ] || continue
    echo "KLAB_INSMOD $m"
    case "$(uname -r)" in
      2.0.*)
        # Linux 2.0 predates query_module(2), /proc/modules, and the printk
        # export used by later probe modules. Its matching Slink loader's zero
        # exit status is followed by a real rmmod below, proving the lifecycle.
        if /sbin/linux20/insmod "$m"; then
            printf 7 > /tmp/klab_coord_loaded
            echo "KLAB_INSMOD_LINUX20 $m"
        else
            echo "KLAB_INSMOD_FAILED $m"
            rc=90
            break
        fi
        ;;
      2.2.*|2.6.16*)
        # Linux 2.2 and 2.6.16 publish the module, but their legacy userspace
        # caller can remain stuck returning from sys_init_module.
        insmod "$m" &
        insert_pid=$!
        module_name=${m##*/}; module_name=${module_name%.ko}; module_name=${module_name%.o}
        insert_wait=0
        while [ "$insert_wait" -lt 10 ]; do
            grep -q "^$module_name " /proc/modules && break
            kill -0 "$insert_pid" 2>/dev/null || break
            sleep 1
            insert_wait=$((insert_wait+1))
        done
        if grep -q "^$module_name " /proc/modules; then
            echo "KLAB_INSMOD_DETACHED $m pid=$insert_pid"
        else
            echo "KLAB_INSMOD_FAILED $m"
            rc=90
            break
        fi
        ;;
      *)
        if ! insmod "$m"; then
            echo "KLAB_INSMOD_FAILED $m"
            rc=90
            break
        fi
        ;;
    esac
done

if [ "$rc" -eq 0 ]; then
    case "$(uname -r)" in
      2.0.*|2.2.*)
        # A second BusyBox 0.60 ash can block on these kernels. Run the test in
        # a subshell of the proven init ash while retaining isolated set/exit state.
        test_text="$(cat /test/test.sh)"
        ( eval "$test_text" ) || rc=$?
        ;;
      *) /bin/sh /test/test.sh || rc=$? ;;
    esac
fi

if [ "$rc" -eq 0 ]; then
    case "$(uname -r)" in
      2.0.*)
        if /sbin/linux20/rmmod klab_coord; then
            rm -f /tmp/klab_coord_loaded
            echo KLAB_RMMOD_LINUX20
        else
            echo KLAB_RMMOD_FAILED_LINUX20
            rc=91
        fi
        ;;
    esac
fi

echo "KLAB_DMESG_BEGIN"
case "$(uname -r)" in
  2.0.*|2.2.*|2.6.16*) dmesg | tail -n 80 || dmesg || true ;;
  *) dmesg || true ;;
esac
echo "KLAB_DMESG_END"
dmesg -n 1 2>/dev/null || true

if [ "$rc" -eq 0 ]; then
    echo "KLAB_RESULT=PASS"
else
    echo "KLAB_RESULT=FAIL rc=$rc"
fi
sync
poweroff -f 2>/dev/null || reboot -f 2>/dev/null || true
sleep 2
exit "$rc"
EOINIT
  chmod +x "$root/init"

  say "Creating initramfs"
  (cd "$root" && find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -1) > "$image"
  printf '%s\n' "$image"
}


legacy_block_initrd_target() {
  [[ "$1" == upstream:v2.[0-5].* ]]
}

legacy_guest_busybox_target() {
  local target="$1" minor
  [[ "$target" == upstream:v2.* ]] && return 0
  if [[ "$target" =~ ^upstream:v3\.([0-9]+)$ ]]; then
    minor="${BASH_REMATCH[1]}"
    (( minor <= 11 )) && return 0
  fi
  return 1
}


make_legacy_ext2_initrd() {
  local root="$1" image="$2" size="${3:-}" raw used_kib
  if [[ -z "$size" ]]; then
    # Account for ext2 metadata, directories, and runtime scratch space. The
    # Linux 2.0/2.2 compatibility overlay includes glibc, Dropbear, and
    # modutils and no longer fits the historical fixed 4 MiB image.
    used_kib="$(du -sk "$root" | awk '{print $1}')"
    size="$((used_kib + 4096))K"
  fi
  raw="${image%.gz}"
  have mkfs.ext2 || die "pre-2.6 guest boot requires mkfs.ext2 (e2fsprogs)"
  have debugfs || die "pre-2.6 guest boot requires debugfs (e2fsprogs)"
  rm -f "$raw" "$image"
  truncate -s "$size" "$raw"
  mkfs.ext2 -q -F -r 0 -b 1024 -I 128 -O none -m 0 -d "$root" "$raw" >/dev/null
  # The rootless host cannot mknod in the staging tree. Inject the static
  # pre-devtmpfs nodes into ext2 metadata without mounting the image.
  { printf '%s\n' \
      'cd /dev' \
      'mknod console c 5 1' \
      'mknod null c 1 3' \
      'mknod random c 1 8' \
      'mknod urandom c 1 9' \
      'mknod ttyS0 c 4 64' \
      'mknod ttyS1 c 4 65' \
      'set_inode_field /dev/console mode 020600' \
      'set_inode_field /dev/null mode 020666' \
      'set_inode_field /dev/random mode 020666' \
      'set_inode_field /dev/urandom mode 020666' \
      'set_inode_field /dev/ttyS0 mode 020600' \
      'set_inode_field /dev/ttyS1 mode 020600';
    } | debugfs -w "$raw" >/dev/null 2>&1
  gzip -1c "$raw" > "$image"
  rm -f "$raw"
}

make_legacy_linux16_boot_iso() {
  local build="$1" kernel="$2" version="$3" out="$build/.klab-linux16-boot.iso"
  local init_source="$SELF_DIR/legacy/minimal-init-linux22.c" label="Linux 2.2.26"
  if [[ "$version" == v2.0.40 ]]; then init_source="$SELF_DIR/legacy/minimal-init-linux20.c"; label="Linux 2.0.40"; fi
  local work root image iso_tree tools="$ARTIFACTS/host-tools/xorriso/root"
  local tool_path="${PATH}" tool_lib="${LD_LIBRARY_PATH:-}"
  have gcc || die "legacy linux16 boot media requires gcc with i386 code generation"
  have grub-mkrescue || die "legacy linux16 boot media requires grub-mkrescue"
  [[ -f "$init_source" ]] || die "$label minimal init source is missing"
  [[ -f "$kernel" ]] || die "$label boot media kernel is missing: $kernel"

  if ! have xorriso || ! have mformat; then
    [[ -x "$tools/usr/bin/xorriso" && -x "$tools/usr/bin/mformat" ]] ||
      die "legacy linux16 boot media requires xorriso and mtools (install them or cache them under $tools)"
    tool_path="$tools/usr/bin:$tool_path"
    tool_lib="$tools/usr/lib/x86_64-linux-gnu${tool_lib:+:$tool_lib}"
  fi

  work="$(mktemp -d)"
  root="$work/root"; image="$work/initrd.ext2.gz"; iso_tree="$work/iso"
  mkdir -p "$root/dev" "$iso_tree/boot/grub"
  gcc -m32 -Os -nostdlib -static -fno-stack-protector -fno-pie -no-pie \
    -Wl,-e,_start -Wl,--build-id=none \
    -o "$root/init" "$init_source" || {
      rm -rf "$work"; die "failed to compile $label minimal init";
    }
  if [[ "$version" == v2.0.40 ]]; then
    make_legacy_ext2_initrd "$root" "$image" 512K
  else
    make_legacy_ext2_initrd "$root" "$image"
  fi
  if [[ "$version" == v2.0.40 ]]; then
    gzip -dc "$image" > "$work/initrd.ext2"
    image="$work/initrd.ext2"
  fi
  cp "$kernel" "$iso_tree/boot/vmlinuz"
  cp "$image" "$iso_tree/boot/initrd.img"
  cat > "$iso_tree/boot/grub/grub.cfg" <<EOF_LEGACY_GRUB
serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
terminal_input serial
terminal_output serial
set timeout=0
set default=0
menuentry 'KLab $label' {
  echo KLAB_GRUB_LOADING_KERNEL
  linux16 /boot/vmlinuz console=ttyS0 root=/dev/ram0 ro init=/init debug vga=0xfffe
  echo KLAB_GRUB_LOADING_INITRD
  initrd16 /boot/initrd.img
  echo KLAB_GRUB_BOOTING
  boot
}
EOF_LEGACY_GRUB
  rm -f "$out"
  PATH="$tool_path" LD_LIBRARY_PATH="$tool_lib" grub-mkrescue -o "$out" "$iso_tree" >/dev/null 2>&1 || {
    rm -rf "$work"; die "failed to create $label GRUB linux16 ISO";
  }
  rm -rf "$work"
  [[ -s "$out" ]] || die "$label GRUB linux16 ISO is empty"
}

make_legacy_linux16_runtime_iso() {
  local kernel="$1" initrd="$2" target="$3" out="$4" work iso_tree tools tool_path tool_lib legacy_net_args=""
  [[ -f "$kernel" && -f "$initrd" ]] || die "legacy runtime ISO inputs are incomplete"
  work="$(mktemp -d)"; iso_tree="$work/iso"; mkdir -p "$iso_tree/boot/grub"
  cp "$kernel" "$iso_tree/boot/vmlinuz"
  if [[ "$target" == upstream:v2.0.40 ]]; then
    gzip -dc "$initrd" > "$iso_tree/boot/initrd.img"
  else
    cp "$initrd" "$iso_tree/boot/initrd.img"
  fi
  [[ "$target" != upstream:v2.0.40 ]] || legacy_net_args=' ether=9,0x300,eth0'
  cat > "$iso_tree/boot/grub/grub.cfg" <<EOF_LEGACY_RUNTIME_GRUB
serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1
terminal_input serial
terminal_output serial
set timeout=0
set default=0
menuentry 'KLab legacy runtime' {
  linux16 /boot/vmlinuz console=ttyS0 root=/dev/ram0 rw init=/init ramdisk_size=32768 debug vga=0xfffe${legacy_net_args}
  initrd16 /boot/initrd.img
  boot
}
EOF_LEGACY_RUNTIME_GRUB
  tools="$ARTIFACTS/host-tools/xorriso/root"; tool_path="$PATH"; tool_lib="${LD_LIBRARY_PATH:-}"
  if ! have xorriso || ! have mformat; then
    tool_path="$tools/usr/bin:$tool_path"
    tool_lib="$tools/usr/lib/x86_64-linux-gnu${tool_lib:+:$tool_lib}"
  fi
  rm -f "$out"
  PATH="$tool_path" LD_LIBRARY_PATH="$tool_lib" grub-mkrescue -o "$out" "$iso_tree" >/dev/null 2>&1 || {
    rm -rf "$work"; die "failed to create runtime Linux16 ISO for $target";
  }
  rm -rf "$work"
  [[ -s "$out" ]] || die "runtime Linux16 ISO is empty for $target"
}

compress_session_initramfs() {
  if have pigz; then pigz -1; else gzip -1; fi
}

install_session_network_modules() {
  local root="$1" target="$2" src rel dst release copied=0
  [[ -n "$target" && "$target" != upstream:* ]] || return 0
  bundle_load "$target"
  [[ -n "${BUNDLE_MODULES_DIR:-}" && -d "$BUNDLE_MODULES_DIR" ]] || return 0
  release="${BUNDLE_KERNEL_RELEASE:-$(basename "$BUNDLE_MODULES_DIR")}"; mkdir -p "$root/lib/modules/$release"
  while IFS= read -r -d '' src; do
    rel="${src#"$BUNDLE_MODULES_DIR"/}"; rel="${rel%.zst}"; rel="${rel%.xz}"; rel="${rel%.gz}"
    dst="$root/lib/modules/$release/$rel"; mkdir -p "$(dirname "$dst")"
    case "$src" in
      *.zst) zstd -dc "$src" > "$dst" || return 1 ;;
      *.xz) xz -dc "$src" > "$dst" || return 1 ;;
      *.gz) gzip -dc "$src" > "$dst" || return 1 ;;
      *) cp "$src" "$dst" || return 1 ;;
    esac
    copied=1
  done < <(find "$BUNDLE_MODULES_DIR" -type f \( -name 'e1000.ko*' -o -name 'virtio_net.ko*' -o -name 'virtio.ko*' -o -name 'virtio_ring.ko*' -o -name 'virtio_pci.ko*' -o -name 'virtio_pci_legacy_dev.ko*' -o -name 'virtio_pci_modern_dev.ko*' -o -name 'net_failover.ko*' -o -name 'failover.ko*' -o -name 'pcnet32.ko*' \) -print0)
  ((copied == 0)) || depmod -b "$root" "$release" 2>/dev/null || return 1
}

make_session_initramfs() {
  local key="$1" target="${2:-}" ssh_authorized_key="${3:-}" include_network_modules="${4:-0}" include_ssh="${5:-0}"
  local root="$INITRAMFS/$key.session.root" image="$INITRAMFS/$key.session.cpio.gz"
  [[ ${KLAB_SESSION_PRELOAD_LOCAL+x} ]] || KLAB_SESSION_PRELOAD_LOCAL=()
  [[ ${KLAB_SESSION_PRELOAD_REMOTE+x} ]] || KLAB_SESSION_PRELOAD_REMOTE=()
  if [[ -d "$root" ]]; then chmod -R u+w "$root" 2>/dev/null || true; fi
  rm -rf "$root"
  mkdir -p "$root"
  local control_tty
  populate_guest_root "$root" "$ACTIVE_USERSPACE_SPEC" "$ARCH"
  local preload_i preload_src preload_dst preload_mode
  for ((preload_i=0; preload_i<${#KLAB_SESSION_PRELOAD_LOCAL[@]}; preload_i++)); do
    preload_src="${KLAB_SESSION_PRELOAD_LOCAL[$preload_i]}"; preload_dst="${KLAB_SESSION_PRELOAD_REMOTE[$preload_i]}"
    mkdir -p "$root$(dirname "$preload_dst")" || die "failed to create preload destination for $preload_dst"
    cp "$preload_src" "$root$preload_dst" || die "failed to preload $preload_src"
    preload_mode=0644; [[ -x "$preload_src" ]] && preload_mode=0755; chmod "$preload_mode" "$root$preload_dst"
  done
  if [[ "$ACTIVE_USERSPACE_SPEC" == native:* ]]; then
    # Captured OCI roots preserve read-only directory modes (Fedora commonly
    # ships /lib as 0555). Session assembly must be able to inject the exact
    # target module tree without mutating the immutable captured root.
    chmod u+w "$root" "$root/root" "$root/etc" "$root/var" "$root/tmp" "$root/lib" "$root/usr" "$root/usr/lib" "$root/usr/lib/modules" 2>/dev/null || true
  fi
  if [[ "$include_network_modules" == 1 ]]; then
    install_session_network_modules "$root" "$target" || die "failed to install session network modules for $target"
  fi
  if [[ "$include_ssh" == 1 ]]; then
    # Legacy BusyBox-only roots predate account databases. Dropbear requires
    # getpwnam(root), so provide the smallest valid root account in the
    # disposable initramfs when the selected userspace has none.
    mkdir -p "$root/etc" "$root/root"
    chmod 0700 "$root/root"
    [[ -s "$root/etc/passwd" ]] || printf '%s\n' 'root:x:0:0:root:/root:/bin/sh' > "$root/etc/passwd"
    [[ -s "$root/etc/group" ]] || printf '%s\n' 'root:x:0:' > "$root/etc/group"
    [[ -s "$root/etc/shadow" ]] || printf '%s\n' 'root:x:19000:0:99999:7:::' > "$root/etc/shadow"
    chmod 0600 "$root/etc/shadow"
    # SSH is a runtime capability, not a reason to bind a second copy of the
    # kernel package to buildroot:ssh. Reuse an existing daemon when present,
    # otherwise inject the architecture-matched static Dropbear fallback into
    # this disposable initramfs. The packaged userspace remains immutable.
    install_native_ssh_backend "$root" "$ARCH" "$target" || die "failed to install an SSH backend for $target [$ARCH]"
  fi
  if [[ "$include_ssh" == 1 && ( "$target" == upstream:v2.0.40 || "$target" == upstream:v2.2.26 ) ]]; then
    local entropy_helper="$GUESTS/helpers/legacy-add-entropy/i386/klab-add-entropy"
    if [[ ! -x "$entropy_helper" || "$entropy_helper" -ot "$SELF_DIR/legacy/klab-add-entropy.c" ]]; then
      mkdir -p "$(dirname "$entropy_helper")"
      gcc -m32 -Os -nostdlib -static -fno-pie -no-pie -fno-stack-protector -Wl,-e,_start -Wl,--build-id=none -o "$entropy_helper.tmp.$$" "$SELF_DIR/legacy/klab-add-entropy.c" || die "failed to build Linux 2.0/2.2 entropy helper"
      chmod 0755 "$entropy_helper.tmp.$$"; mv "$entropy_helper.tmp.$$" "$entropy_helper"
      sha256sum "$entropy_helper" > "$entropy_helper.sha256"
    fi
    install -m 0755 "$entropy_helper" "$root/bin/klab-add-entropy"
    dd if=/dev/urandom of="$root/etc/klab-entropy" bs=64 count=1 status=none || die "could not seed legacy guest entropy artifact"
    chmod 0600 "$root/etc/klab-entropy"
  fi
  if [[ "$ACTIVE_USERSPACE_SPEC" == native:* && -n "$target" && "$target" != upstream:* ]]; then
    bundle_load "$target"
    if [[ -n "${BUNDLE_MODULES_DIR:-}" && -d "$BUNDLE_MODULES_DIR" ]]; then
      mkdir -p "$root/lib/modules"
      cp -a "$BUNDLE_MODULES_DIR" "$root/lib/modules/$BUNDLE_KERNEL_RELEASE"
      if [[ ! -s "$root/lib/modules/$BUNDLE_KERNEL_RELEASE/modules.dep" ]]; then
        depmod -b "$root" "$BUNDLE_KERNEL_RELEASE" 2>/dev/null || true
      fi
    fi
  fi
  control_tty="$(linux_session_control_tty "$ARCH" "$target")"
  if [[ -n "$ssh_authorized_key" ]]; then
    [[ -s "$ssh_authorized_key" ]] || die "SSH authorized key is missing or empty: $ssh_authorized_key"
    mkdir -p "$root/root/.ssh" || die "could not create guest root SSH directory"
    cp "$ssh_authorized_key" "$root/root/.ssh/authorized_keys" || die "could not install guest authorized key"
    chmod 0700 "$root/root/.ssh" || die "could not secure guest root SSH directory"
    chmod 0600 "$root/root/.ssh/authorized_keys" || die "could not secure guest authorized key"
  fi

  cat > "$root/init" <<'EOINIT'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mkdir -p /dev
# Some rootfs archives contain regular placeholder files. On kernels predating
# devtmpfs, mknod cannot replace them, so remove only non-device placeholders.
[ ! -e /dev/null ] || [ -c /dev/null ] || rm -f /dev/null
[ ! -e /dev/random ] || [ -c /dev/random ] || rm -f /dev/random
[ ! -e /dev/urandom ] || [ -c /dev/urandom ] || rm -f /dev/urandom
[ -c /dev/null ] || /bin/busybox mknod /dev/null c 1 3 2>/tmp/klab-mknod.err || true
[ -c /dev/random ] || /bin/busybox mknod /dev/random c 1 8 2>/tmp/klab-mknod.err || true
[ -c /dev/urandom ] || /bin/busybox mknod /dev/urandom c 1 9 2>/tmp/klab-mknod.err || true
chmod 666 /dev/null /dev/random /dev/urandom 2>/dev/null || true
modprobe e1000 2>/dev/null || true
# virtio_net does not depend on a transport; load the PCI transport first so
# modular cloud kernels bind the QEMU NIC before network configuration.
modprobe virtio_pci 2>/dev/null || true
modprobe virtio_net 2>/dev/null || true
# devtmpfs arrived after the earliest supported kernels. Create the second
# UART node explicitly when those kernels reach this initramfs without /dev.
if [ ! -c @KLAB_CONTROL_TTY@ ]; then
    mkdir -p /dev
    case @KLAB_CONTROL_TTY@ in
        /dev/ttyS1) /bin/busybox mknod @KLAB_CONTROL_TTY@ c 4 65 2>/dev/null || true ;;
        /dev/ttyAMA1) /bin/busybox mknod @KLAB_CONTROL_TTY@ c 204 65 2>/dev/null || true ;;
    esac
fi
mkdir -p /tmp/klab

echo "KLAB_SESSION_BOOT kernel=$(uname -r)"

i=0
while [ ! -c @KLAB_CONTROL_TTY@ ] && [ "$i" -lt 100 ]; do
    i=$((i + 1))
    sleep 0.05
done
if [ ! -c @KLAB_CONTROL_TTY@ ]; then
    echo "KLAB_SESSION_ERROR @KLAB_CONTROL_TTY@ unavailable"
    sleep 2
    poweroff -f 2>/dev/null || reboot -f 2>/dev/null || true
fi

stty -opost -echo clocal cread <@KLAB_CONTROL_TTY@ >@KLAB_CONTROL_TTY@ 2>/dev/null || stty -F @KLAB_CONTROL_TTY@ 115200 raw -echo cread clocal -crtscts 2>/dev/null || true
exec 3<>@KLAB_CONTROL_TTY@
echo "KLAB_SESSION_READY kernel=$(uname -r)"
# QEMU may discard early UART output before the host relay attaches. A POSIX
# heartbeat makes readiness observable without the non-portable `read -t`.
(while :; do printf 'READY %s\n' "$(uname -r)" >&3; sleep 1; done) &

put_token=""
put_path=""
put_mode=""
control_ready=0
while :; do
    if [ "$control_ready" -eq 0 ]; then
        # QEMU drops serial bytes until a host client attaches. Retry the
        # greeting so fast legacy kernels cannot lose the one-time READY frame.
        printf 'READY %s\n' "$(uname -r)" >&3
        # POSIX read has no timeout option. Blocking here works for BusyBox ash,
        # Ubuntu dash, and historical shells: the host relay's PING releases it
        # even when QEMU discarded the earlier READY greeting.
        if ! IFS= read -r line <&3; then
            continue
        fi
        control_ready=1
    elif ! IFS= read -r line <&3; then
        exec 3>&- 3<&-
        sleep 0.05
        until exec 3<>@KLAB_CONTROL_TTY@; do
            sleep 0.05
        done
        control_ready=0
        continue
    fi
    set -- $line
    verb="${1:-}"
    case "$verb" in
      PING)
        printf 'PONG %s\n' "${2:-0}" >&3
        ;;
      EXEC)
        token="${2:-}"
        encoded="${3:-}"
        cmdfile="/tmp/klab/cmd.$token"
        outfile="/tmp/klab/out.$token"
        # BusyBox 0.60 ash can block while reading a regular script file on
        # Linux 2.0/2.2. Stream decoded commands to its stdin instead. The
        # shell is the last pipeline member, so historical ash reports its rc.
        # BusyBox 0.60 ash can block when a child ash reads a regular file or
        # pipe on Linux 2.0/2.2. Decode through command substitution, which is
        # known to work there, and evaluate in this long-lived control shell.
        command_text="$(printf '%s' "$encoded" | base64 -d 2>/dev/null)"
        ( eval "$command_text" ) >"$outfile" 2>&1
        rc=$?
        printf 'BEGIN %s %s\n' "$token" "$rc" >&3
        base64 "$outfile" 2>/dev/null | while IFS= read -r b64; do
            printf 'DATA %s %s\n' "$token" "$b64" >&3
        done
        printf 'END %s %s\n' "$token" "$rc" >&3
        rm -f "$cmdfile" "$outfile"
        ;;
      PUT)
        token="${2:-}"
        path64="${3:-}"
        mode="${4:-0644}"
        path="$(printf '%s' "$path64" | base64 -d 2>/dev/null || true)"
        case "$path" in
          /*) ;;
          *) printf 'PUTERR %s invalid-path\n' "$token" >&3; put_token=""; continue ;;
        esac
        parent="${path%/*}"
        [ -n "$parent" ] || parent=/
        mkdir -p "$parent"
        : > "$path" || { printf 'PUTERR %s create-failed\n' "$token" >&3; put_token=""; continue; }
        put_token="$token"; put_path="$path"; put_mode="$mode"
        ;;
      DATA)
        token="${2:-}"
        seq="${3:-}"
        data="${4:-}"
        if [ -n "$put_token" ] && [ "$token" = "$put_token" ]; then
            if printf '%s' "$data" | base64 -d >> "$put_path" 2>/dev/null; then
                printf 'DATAOK %s %s\n' "$token" "$seq" >&3
            else
                printf 'DATAERR %s %s\n' "$token" "$seq" >&3
            fi
        fi
        ;;
      ENDPUT)
        token="${2:-}"
        if [ -n "$put_token" ] && [ "$token" = "$put_token" ]; then
            chmod "$put_mode" "$put_path" 2>/dev/null || true
            size="$(wc -c < "$put_path" 2>/dev/null || echo 0)"
            printf 'PUTOK %s %s\n' "$token" "$size" >&3
        else
            printf 'PUTERR %s no-active-put\n' "$token" >&3
        fi
        put_token=""; put_path=""; put_mode=""
        ;;
      *)
        printf 'ERROR unknown-command\n' >&3
        ;;
    esac
done
EOINIT
  sed -i "s#@KLAB_CONTROL_TTY@#$control_tty#g" "$root/init"
  chmod +x "$root/init"
  if legacy_block_initrd_target "$target"; then
    image="$INITRAMFS/$key.session.ext2.gz"
    make_legacy_ext2_initrd "$root" "$image"
  else
    (cd "$root" && find . -print0 | cpio --null -o --owner=0:0 --format=newc 2>/dev/null | compress_session_initramfs) > "$image"
  fi
  printf '%s\n' "$image"
}

session_dir() { printf '%s/%s\n' "$SESSIONS" "$1"; }

session_require_running() {
  local name="$1" dir pid sock=""
  dir="$(session_dir "$name")"
  [[ -f "$dir/pid" ]] || die "unknown session '$name'"
  pid="$(cat "$dir/pid")"
  kill -0 "$pid" 2>/dev/null || die "session '$name' is not running (stale pid $pid)"
  if [[ -f "$dir/session.env" ]]; then
    unset SESSION_CONTROL
    # shellcheck disable=SC1090
    source "$dir/session.env"
    sock="${SESSION_CONTROL:-}"
  fi
  [[ -n "$sock" && -S "$sock" ]] || die "session '$name' control socket is unavailable"
}

session_rpc_exec() {
  local socket="$1" command="$2" timeout_seconds="${3:-30}"
  python3 -S - "$socket" "$command" "$timeout_seconds" <<'PYRPC'
import base64, socket, sys, time, uuid
path, cmd, timeout_text = sys.argv[1:]
tok = uuid.uuid4().hex[:16]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
end = time.time() + 10
while True:
    try:
        s.connect(path); break
    except OSError:
        if time.time() >= end: raise
        time.sleep(.1)
s.settimeout(float(timeout_text))
f = s.makefile('rwb', buffering=0)
payload = base64.b64encode(cmd.encode()).decode()
f.write(f"EXEC {tok} {payload}\n".encode())
out = bytearray(); rc = None
while True:
    line = f.readline()
    if not line:
        raise SystemExit('control channel closed before response')
    parts = line.decode('ascii','replace').rstrip('\r\n').split(' ',2)
    if parts[0] == 'DATA' and len(parts) == 3 and parts[1] == tok:
        out.extend(base64.b64decode(parts[2]))
    elif parts[0] == 'END' and len(parts) >= 3 and parts[1] == tok:
        rc = int(parts[2]); break
sys.stdout.buffer.write(out)
f.close()
s.close()
raise SystemExit(rc if rc is not None else 126)
PYRPC
}

session_rpc_boot_ready() {
  local socket="$1" timeout_seconds="$2"
  python3 - "$socket" "$timeout_seconds" <<'PYRPC'
import base64, socket, sys, time, uuid
path, timeout_text = sys.argv[1:]
deadline = time.monotonic() + float(timeout_text)
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
while True:
    try:
        s.connect(path)
        break
    except OSError:
        if time.monotonic() >= deadline:
            raise SystemExit('control socket did not accept a connection before timeout')
        time.sleep(.1)
f = s.makefile('rwb', buffering=0)
ready_tok = uuid.uuid4().hex[:16]
f.write(f"PING {ready_tok}\n".encode())
while True:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise SystemExit('guest did not announce control readiness before timeout')
    s.settimeout(remaining)
    line = f.readline()
    if not line:
        raise SystemExit('control channel closed before readiness')
    parts = line.decode('ascii', 'replace').rstrip('\r\n').split(' ', 1)
    if parts[0] == 'READY':
        f.write(f"PING {ready_tok}\n".encode())
        continue
    if parts[0] == 'PONG' and len(parts) > 1 and parts[1] == ready_tok:
        break
tok = uuid.uuid4().hex[:16]
payload = base64.b64encode(b'uname -r').decode()
f.write(f"EXEC {tok} {payload}\n".encode())
out = bytearray()
while True:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise SystemExit('guest readiness probe timed out')
    s.settimeout(remaining)
    line = f.readline()
    if not line:
        raise SystemExit('control channel closed during readiness probe')
    parts = line.decode('ascii', 'replace').rstrip('\r\n').split(' ', 2)
    if parts[0] == 'DATA' and len(parts) == 3 and parts[1] == tok:
        out.extend(base64.b64decode(parts[2]))
    elif parts[0] == 'END' and len(parts) >= 3 and parts[1] == tok:
        rc = int(parts[2])
        sys.stdout.buffer.write(out)
        f.close()
        s.close()
        raise SystemExit(rc)
PYRPC
}

session_rpc_put() {
  local socket="$1" local_file="$2" remote="$3" mode="${4:-0644}" flow="${5:-ack}"
  python3 - "$socket" "$local_file" "$remote" "$mode" "$flow" <<'PYRPC'
import base64, os, socket, sys, time, uuid
sockpath, local, remote, mode, flow = sys.argv[1:]
if not os.path.isfile(local):
    raise SystemExit(f"not a regular file: {local}")
if not remote.startswith('/') or '\n' in remote or '\x00' in remote:
    raise SystemExit('remote path must be an absolute path without newlines')
tok = uuid.uuid4().hex[:16]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
end = time.time() + 10
while True:
    try:
        s.connect(sockpath); break
    except OSError:
        if time.time() >= end: raise
        time.sleep(.1)
s.settimeout(float(os.environ.get('KLAB_UPLOAD_ACK_TIMEOUT', '15')))
f = s.makefile('rwb', buffering=0)
p64 = base64.b64encode(remote.encode()).decode()
f.write(f"PUT {tok} {p64} {mode}\n".encode())
def wait_for(kind, seq=None):
    while True:
        line=f.readline()
        if not line: raise SystemExit('control channel closed during upload')
        p=line.decode('ascii','replace').rstrip('\r\n').split(' ',3)
        if len(p) < 2 or p[1] != tok:
            continue
        if p[0] == 'PUTERR':
            raise SystemExit(p[2] if len(p)>2 else 'guest upload failed')
        if p[0] == 'DATAERR':
            raise SystemExit(f'guest rejected upload chunk {p[2] if len(p)>2 else "?"}')
        if p[0] == kind and (seq is None or (len(p)>2 and p[2] == str(seq))):
            return p
seq=0
if flow == 'serial':
    chunk_size = int(os.environ.get('KLAB_SERIAL_UPLOAD_CHUNK', '96'))
    if chunk_size < 12 or chunk_size > 384:
        raise SystemExit('KLAB_SERIAL_UPLOAD_CHUNK must be between 12 and 384 bytes')
else:
    chunk_size = 96
with open(local,'rb') as src:
    while True:
        chunk = src.read(chunk_size)
        if not chunk: break
        seq += 1
        f.write(f"DATA {tok} {seq} {base64.b64encode(chunk).decode()}\n".encode())
        wait_for('DATAOK', seq)
f.write(f"ENDPUT {tok}\n".encode())
p=wait_for('PUTOK')
print(p[2] if len(p)>2 else '0')
s.close()
PYRPC
}


session_rpc_put_exec() {
  local socket="$1" local_file="$2" remote="$3" mode="${4:-0644}"
  python3 - "$socket" "$local_file" "$remote" "$mode" <<'PYRPC'
import base64, os, posixpath, shlex, socket, sys, time, uuid
sockpath, local, remote, mode = sys.argv[1:]
if not os.path.isfile(local):
    raise SystemExit(f"not a regular file: {local}")
if not remote.startswith('/') or '\n' in remote or '\x00' in remote:
    raise SystemExit('remote path must be absolute and contain no newlines')
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
deadline = time.monotonic() + 10
while True:
    try:
        s.connect(sockpath)
        break
    except OSError:
        if time.monotonic() >= deadline:
            raise
        time.sleep(0.1)
s.settimeout(30)
f = s.makefile('rwb', buffering=0)
def execute(command):
    tok = uuid.uuid4().hex[:16]
    payload = base64.b64encode(command.encode()).decode()
    f.write(f"EXEC {tok} {payload}\n".encode())
    out = bytearray()
    while True:
        line = f.readline()
        if not line:
            raise SystemExit('FreeBSD control channel closed during upload')
        parts = line.decode('ascii', 'replace').rstrip('\r\n').split(' ', 2)
        if parts[0] == 'DATA' and len(parts) == 3 and parts[1] == tok:
            out.extend(base64.b64decode(parts[2]))
        elif parts[0] == 'END' and len(parts) >= 3 and parts[1] == tok:
            rc = int(parts[2])
            if rc:
                raise SystemExit(f"FreeBSD upload command failed ({rc}): {out.decode(errors='replace')}")
            return bytes(out)
qremote = shlex.quote(remote)
qparent = shlex.quote(posixpath.dirname(remote))
execute(f"mkdir -p {qparent}; : > {qremote}; chmod {shlex.quote(mode)} {qremote}")
with open(local, 'rb') as src:
    while True:
        chunk = src.read(24)
        if not chunk:
            break
        data = base64.b64encode(chunk).decode()
        execute(f"printf '%s' {shlex.quote(data)} | base64 -d >> {qremote}")
expected = os.path.getsize(local)
raw = execute(f"wc -c < {qremote}").decode().strip()
try:
    actual = int(raw)
except ValueError:
    raise SystemExit(f"invalid FreeBSD upload size response: {raw!r}")
if actual != expected:
    raise SystemExit(f"FreeBSD serial upload size mismatch for {remote}: expected {expected}, got {actual}")
print(actual)
f.close()
s.close()
PYRPC
}

crash_log_has_panic() {
  local log="$1"
  [[ -f "$log" ]] && grep -Eqi 'Kernel panic|not syncing:|PANIC: double fault|(^|[[:space:]])panic:|Fatal trap [0-9]+' "$log"
}

qmp_dump_guest_memory() {
  local socket="$1" outfile="$2" format="${3:-elf}"
  [[ -S "$socket" ]] || return 1
  mkdir -p "$(dirname "$outfile")"
  python3 - "$socket" "$outfile" "$format" <<'PYQMP'
import json, os, socket, sys, time
sockpath, outfile, fmt = sys.argv[1:]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(10)
end = time.time() + 10
while True:
    try:
        s.connect(sockpath); break
    except OSError:
        if time.time() >= end: raise
        time.sleep(.1)
f = s.makefile('rwb', buffering=0)
def recv_obj(timeout=120):
    s.settimeout(timeout)
    while True:
        line=f.readline()
        if not line: raise RuntimeError('QMP channel closed')
        obj=json.loads(line)
        if 'event' in obj: continue
        return obj
hello=recv_obj(10)
f.write(b'{"execute":"qmp_capabilities"}\n')
r=recv_obj(10)
if 'error' in r: raise RuntimeError(r['error'])
# Freeze virtual CPUs before taking the snapshot.
f.write(b'{"execute":"stop"}\n')
r=recv_obj(10)
if 'error' in r: raise RuntimeError(r['error'])
args={"paging":False,"protocol":"file:"+os.path.abspath(outfile),"format":fmt}
f.write((json.dumps({"execute":"dump-guest-memory","arguments":args})+'\n').encode())
r=recv_obj(600)
if 'error' in r: raise RuntimeError(r['error'])
s.close()
PYQMP
}

stable_vmlinux_image() {
  local target="$1" profile="${2:-normal}" provider raw dir build="" arch="${ARCH}"
  provider="${target%%:*}"
  if [[ "$provider" == upstream ]]; then
    raw="${target#upstream:}"
    dir="$(imported_upstream_dir "$raw" "$profile" "$arch")"
    if [[ -f "$dir/bundle.env" ]]; then
      reset_bundle_toolchain_vars
      # shellcheck disable=SC1090
      source "$dir/bundle.env"
      [[ -f "${BUNDLE_BUILD_DIR:-}/vmlinux" ]] && printf '%s\n' "$BUNDLE_BUILD_DIR/vmlinux"
    else
      build="$(resolve_upstream_build_dir "$raw" "$profile" "$arch" 2>/dev/null || true)"
      [[ -n "$build" && -f "$build/vmlinux" ]] && printf '%s\n' "$build/vmlinux"
    fi
  fi
}

archive_crash_artifacts() {
  local id="$1" target="$2" profile="$3" console="$4" kernel="$5" vmcore="${6:-}" session_dir_src="${7:-}"
  local stamp out vmlinux=""
  stamp="$(date +%Y%m%d-%H%M%S)"
  out="$CRASHES/${id}-${stamp}"
  mkdir -p "$out"
  [[ -f "$console" ]] && cp "$console" "$out/console.log"
  [[ -f "$kernel" ]] && ln -s "$kernel" "$out/kernel-image" 2>/dev/null || true
  vmlinux="$(stable_vmlinux_image "$target" "$profile" 2>/dev/null || true)"
  [[ -n "$vmlinux" && -f "$vmlinux" ]] && ln -s "$vmlinux" "$out/vmlinux" 2>/dev/null || true
  [[ -n "$vmcore" && -f "$vmcore" ]] && mv "$vmcore" "$out/vmcore"
  if [[ -n "$session_dir_src" && -d "$session_dir_src" ]]; then
    [[ -f "$session_dir_src/loaded-modules.tsv" ]] && cp "$session_dir_src/loaded-modules.tsv" "$out/"
    [[ -f "$session_dir_src/qemu-error.log" ]] && cp "$session_dir_src/qemu-error.log" "$out/"
  fi
  {
    printf 'CRASH_ID=%q\n' "$(basename "$out")"
    printf 'TARGET=%q\n' "$target"
    printf 'PROFILE=%q\n' "$profile"
    printf 'KERNEL_IMAGE=%q\n' "$kernel"
    printf 'VMLINUX=%q\n' "$vmlinux"
    printf 'VMCORE=%q\n' "$( [[ -f "$out/vmcore" ]] && printf '%s' "$out/vmcore" || true )"
    printf 'CAPTURED_AT=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$out/crash.env"
  tail -n 400 "$console" > "$out/console-tail.log" 2>/dev/null || true
  printf '%s\n' "$out"
}

run_qemu_image_crashaware() {
  local key="$1" kernel_image="$2" initrd="$3" crashdump="${4:-0}" panic_on_warn="${5:-0}"
  local target="${6:-$key}" profile="${7:-normal}"
  local stamp log hostlog qmp pid start status=running i append crash_tmp='' crash_dir='' qrc=0
  [[ "$crashdump" == 1 ]] && validate_crashdump_format
  stamp="$(date +%Y%m%d-%H%M%S)"
  log="$LOGS/$key-$stamp.log"
  hostlog="$LOGS/$key-$stamp.qemu.log"
  qmp="/tmp/klab-qmp-${UID:-$(id -u)}-$(printf '%s' "$key-$stamp" | sha256sum | cut -c1-12).sock"
  rm -f "$qmp"
  if legacy_block_initrd_target "$target"; then
    local legacy_root="${initrd%.cpio.gz}.root" legacy_initrd="${initrd%.cpio.gz}.ext2.gz"
    [[ -d "$legacy_root" ]] || die "legacy block-initrd root is missing: $legacy_root"
    make_legacy_ext2_initrd "$legacy_root" "$legacy_initrd"
    initrd="$legacy_initrd"
    append="console=$(linux_session_console "$ARCH" "$target") root=/dev/ram0 rw init=/init panic=0 oops=panic loglevel=7"
  else
    append="console=$(linux_session_console "$ARCH" "$target") rdinit=/init panic=0 oops=panic loglevel=7"
  fi
  [[ "$panic_on_warn" == 1 ]] && append+=' panic_on_warn=1'
  local qemu; qemu="$(require_qemu_arch "$ARCH")"
  local accel=() qmem qcpus; mapfile -t accel < <(qemu_accel_args "$ARCH")
  qmem="$(qemu_memory_for_arch "$ARCH")"; qcpus="$(qemu_cpus_for_arch "$ARCH")"
  [[ "$ACTIVE_USERSPACE_SPEC" == native:* ]] && qmem="$NATIVE_MEMORY"
  if [[ ( "$target" == upstream:v2.* || "$target" == upstream:v3.[0-9] || "$target" == upstream:v3.1[01] ) && ( "$ARCH" == x86_64 || "$ARCH" == i386 ) ]]; then
    if [[ "$target" == upstream:v2.6.16 && "$ARCH" == x86_64 ]] && qemu_kvm_compatible "$ARCH"; then mapfile -t accel < <(qemu_accel_args "$ARCH"); elif [[ "$target" == upstream:v2.0.40 && "$ARCH" == i386 ]]; then accel=(-accel tcg -cpu pentium3); elif [[ "$target" == upstream:v2.2.26 && "$ARCH" == i386 ]]; then accel=(-accel tcg -cpu pentium3); elif [[ "$ARCH" == i386 ]]; then accel=(-accel tcg -cpu qemu32); else accel=(-accel tcg -cpu qemu64); fi
    qmem=256M; qcpus=1
  fi
  say "Booting QEMU [$ARCH]; log: $log"
  local -a test_boot_media
  if legacy_block_initrd_target "$target" && [[ "$target" == upstream:v2.0.40 || "$target" == upstream:v2.2.26 ]]; then
    local legacy_test_iso="${initrd%.ext2.gz}.linux16.iso"
    make_legacy_linux16_runtime_iso "$kernel_image" "$initrd" "$target" "$legacy_test_iso"
    test_boot_media=(-cdrom "$legacy_test_iso" -boot d)
  else
    test_boot_media=(-kernel "$kernel_image" -initrd "$initrd" -append "$append")
  fi
  "$qemu" "${accel[@]}" -machine "$(qemu_machine_for_arch "$ARCH")" -m "$qmem" -smp "$qcpus" \
    "${test_boot_media[@]}" \
    -display none -net none -serial "file:$log" -qmp "unix:$qmp,server=on,wait=off" \
    -monitor none -no-reboot >"$hostlog" 2>&1 &
  pid=$!
  for ((i=0; i<BOOT_TIMEOUT*10; i++)); do
    if grep -q '^KLAB_RESULT=PASS' "$log" 2>/dev/null; then status=pass; break; fi
    if grep -q '^KLAB_RESULT=FAIL' "$log" 2>/dev/null; then status=fail; break; fi
    if crash_log_has_panic "$log"; then status=crash; break; fi
    if ! kill -0 "$pid" 2>/dev/null; then status=exit; break; fi
    sleep 0.1
  done
  if [[ "$status" == running ]]; then status=timeout; fi

  if [[ "$status" == crash ]]; then
    say "CRASH: kernel panic detected for $key"
    if [[ "$crashdump" == 1 ]]; then
      crash_tmp="$CRASHES/.${key}-${stamp}.vmcore.tmp"
      say "Capturing QEMU guest-memory vmcore ($CRASHDUMP_FORMAT); this may be about the size of guest RAM"
      if ! qmp_dump_guest_memory "$qmp" "$crash_tmp" "$CRASHDUMP_FORMAT"; then
        say "Warning: vmcore capture failed; serial crash log will still be retained"
        rm -f "$crash_tmp"
        crash_tmp=''
      fi
    fi
    crash_dir="$(archive_crash_artifacts "$key" "$target" "$profile" "$log" "$kernel_image" "$crash_tmp")"
    say "Crash artifacts: $crash_dir"
  fi

  if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
  wait "$pid" 2>/dev/null || qrc=$?
  rm -f "$qmp"
  cat "$log" 2>/dev/null || true

  case "$status" in
    pass) say "PASS: $key"; return 0 ;;
    crash) return 1 ;;
    timeout) say "FAIL: $key timed out after ${BOOT_TIMEOUT}s" ;;
    fail) say "FAIL: guest test failed for $key" ;;
    *) say "FAIL: guest did not produce a PASS marker (QEMU rc=$qrc)" ;;
  esac
  return 1
}

run_qemu_image() {
  local key="$1" kernel_image="$2" initrd="$3" crashdump="${4:-0}" panic_on_warn="${5:-0}"
  local target="${6:-$key}" profile="${7:-normal}"
  run_qemu_image_crashaware "$key" "$kernel_image" "$initrd" "$crashdump" "$panic_on_warn" "$target" "$profile"
}

run_qemu() {
  local key="$1" build="$2" initrd="$3"
  local a="$(cat "$build/.klab-arch" 2>/dev/null || echo x86_64)"
  set_active_arch "$a"
  run_qemu_image "$key" "$build/$(linux_kernel_image_rel_for_build "$build" "$ARCH")" "$initrd"
}

cmd_build() {
  local raw="$1" profile="${2:-normal}"
  prepare_build "$raw" "$profile"
}

cmd_module() {
  local raw="$1" profile module_dir result build
  if [[ $# -eq 2 ]]; then profile=normal; module_dir="$2"; else profile="$2"; module_dir="$3"; fi
  result="$(prepare_build "$raw" "$profile" | tail -n1)"
  build="${result##*$'\t'}"
  build_external_module "$build" "$module_dir"
  printf 'Built modules:\n'; printf '  %s\n' "${MODULE_FILES[@]}"
}

imported_upstream_dir() {
  local raw="$1" profile="$2" arch="$(canonical_arch "${3:-$ARCH}")" version modern legacy
  version="$(normalize_version "$raw")"
  if [[ "$version" == mainline ]]; then
    modern="$KERNELS/upstream/mainline/$arch/$profile"
    legacy="$KERNELS/upstream/mainline/$profile"
  else
    modern="$KERNELS/upstream/${version#v}/$arch/$profile"
    legacy="$KERNELS/upstream/${version#v}/$profile"
  fi
  if [[ -f "$modern/bundle.env" ]]; then printf '%s\n' "$modern"
  elif [[ "$arch" == x86_64 && -f "$legacy/bundle.env" ]]; then printf '%s\n' "$legacy"
  else printf '%s\n' "$modern"; fi
}

cmd_imported_upstream_test() {
  local raw="$1" profile="$2" module_dir="$3" test_script="$4" dir job key initrd
  dir="$(imported_upstream_dir "$raw" "$profile")"
  [[ -f "$dir/bundle.env" ]] || die "no imported upstream bundle for $raw/$profile at $dir"
  reset_bundle_toolchain_vars
  # shellcheck disable=SC1090
  source "$dir/bundle.env"
  [[ -d "$BUNDLE_SOURCE_DIR" && -d "$BUNDLE_BUILD_DIR" && -f "$BUNDLE_KERNEL_IMAGE" ]] || die "imported upstream bundle is incomplete: $dir"
  job="$(copy_module_job "upstream:$raw:$profile" "$module_dir")"
  say "Building external module against imported upstream $raw/$profile"
  prepare_bound_toolchain
  local ext_assignment
  ext_assignment="$(external_module_make_assignment "$BUNDLE_SOURCE_DIR" "$job/module")"
  if [[ "$ext_assignment" == M=* ]]; then
    bound_make -s -C "$BUNDLE_SOURCE_DIR" O="$BUNDLE_BUILD_DIR" "$ext_assignment" clean || true
  fi
  bound_make -C "$BUNDLE_SOURCE_DIR" O="$BUNDLE_BUILD_DIR" "$ext_assignment" -j"$JOBS" modules
  mapfile -t MODULE_FILES < <(find "$job/module" -type f -name '*.ko' -print | sort)
  ((${#MODULE_FILES[@]} > 0)) || die "no .ko files were produced for imported upstream $raw/$profile"
  key="upstream_$(printf '%s' "$raw" | tr ':@/' '___')_${profile}"
  initrd="$(make_initramfs "$key" "$test_script" "${MODULE_FILES[@]}")" || die "failed to create initramfs for $key"
  run_qemu_image "$key" "$BUNDLE_KERNEL_IMAGE" "$initrd"
}

cmd_test_legacy() {
  local raw="$1" profile module_dir test_script result key build initrd
  if [[ "$raw" == *:* ]]; then
    if [[ "${raw%%:*}" == upstream ]]; then
      raw="${raw#upstream:}"
    else
      [[ $# -eq 3 ]] || die "distro target test syntax: $0 test provider:release:kernel module-dir test.sh"
      cmd_distro_test "$raw" "$2" "$3"
      return
    fi
  fi
  if [[ $# -eq 3 ]]; then
    profile=normal; module_dir="$2"; test_script="$3"
  else
    profile="$2"; module_dir="$3"; test_script="$4"
  fi
  if [[ -f "$(imported_upstream_dir "$raw" "$profile")/bundle.env" && ( "$OFFLINE" == 1 || "${KLAB_PREFER_IMPORTED:-0}" == 1 ) ]]; then
    cmd_imported_upstream_test "$raw" "$profile" "$module_dir" "$test_script"
    return
  fi
  [[ "$OFFLINE" != 1 ]] || die "offline mode: upstream $raw/$profile is not imported locally; transfer and import a .klab bundle first"
  result="$(prepare_build "$raw" "$profile" | tail -n1)"
  key="$(printf '%s' "$result" | cut -f3)"
  build="$(printf '%s' "$result" | cut -f5)"
  build_external_module "$build" "$module_dir"
  initrd="$(make_initramfs "$key" "$test_script" "${MODULE_FILES[@]}")" || die "failed to create initramfs for $key"
  run_qemu "$key" "$build" "$initrd"
}

cmd_matrix() {
  local profile="$1" module_dir="$2" test_script="$3"
  shift 3
  (($# > 0)) || die "matrix needs at least one version"
  local total=$# failures=0 v
  for v in "$@"; do
    printf '\n################################################################\n'
    printf '### %s / %s\n' "$v" "$profile"
    printf '################################################################\n'
    if ! cmd_test_legacy "$v" "$profile" "$module_dir" "$test_script"; then
      failures=$((failures + 1))
    fi
  done
  printf '\nMatrix complete: %d failure(s) out of %d kernel(s).\n' "$failures" "$total"
  (( failures == 0 ))
}

cmd_cache() {
  printf 'Upstream build cache: %s\n' "$BUILDS"
  if [[ -d "$BUILDS" ]]; then
    find "$BUILDS" -mindepth 1 -maxdepth 1 -type d -printf '  %f\n' | sort
  fi
  printf '\nDistribution bundles: %s\n' "$KERNELS"
  if [[ -d "$KERNELS" ]]; then
    while IFS= read -r env; do
      printf '  %s\n' "${env#"$KERNELS"/}" | sed 's#/bundle.env$##'
    done < <(find "$KERNELS" -type f -name bundle.env -print 2>/dev/null | sort)
  fi
}

cmd_clean() {
  local version profile="${2:-normal}" pattern
  version="$(normalize_version "$1")"
  if [[ "$version" == mainline ]]; then pattern="mainline-*__${profile}"; else pattern="${version#v}__${profile}"; fi
  say "Removing cached build(s): $pattern"
  rm -rf "$BUILDS"/$pattern "$INITRAMFS"/$pattern* "$LOGS"/$pattern* 2>/dev/null || true
}


# ---------------------------------------------------------------------------
# Distribution-provider layer
# ---------------------------------------------------------------------------

container_runtime() {
  if [[ -n "$CONTAINER_RUNTIME" ]]; then
    have "$CONTAINER_RUNTIME" || die "KLAB_CONTAINER_RUNTIME '$CONTAINER_RUNTIME' was not found"
    printf '%s\n' "$CONTAINER_RUNTIME"
  elif have podman; then
    printf '%s\n' podman
  elif have docker; then
    printf '%s\n' docker
  else
    die "a container runtime is required for distro providers (install podman or docker, or set KLAB_CONTAINER_RUNTIME)"
  fi
}

# Split container-runtime options from the command.  Docker/Podman require
# `run [OPTIONS] IMAGE [COMMAND ...]`; older KLab code appended IMAGE after the
# command, which could accidentally run a completely different image (for
# example the Docker Hub `bash` image for `... IMAGE bash -lc SCRIPT`).
klab_container_split_args() {
  KLAB_CONTAINER_RUN_OPTS=()
  KLAB_CONTAINER_COMMAND=()
  while (($#)); do
    case "$1" in
      -v|--volume|-e|--env|-w|--workdir|--network|--platform|--entrypoint|--name|--hostname|--add-host|--device|--security-opt|--cap-add|--cap-drop|--tmpfs)
        (($# >= 2)) || die "container option '$1' requires a value"
        KLAB_CONTAINER_RUN_OPTS+=("$1" "$2"); shift 2 ;;
      --volume=*|--env=*|--workdir=*|--network=*|--platform=*|--entrypoint=*|--name=*|--hostname=*|--add-host=*|--device=*|--security-opt=*|--cap-add=*|--cap-drop=*|--tmpfs=*)
        KLAB_CONTAINER_RUN_OPTS+=("$1"); shift ;;
      --)
        shift; KLAB_CONTAINER_COMMAND=("$@"); return ;;
      -*)
        # Fail closed instead of silently moving an unknown runtime option to
        # the container command side.
        die "unsupported container run option '$1' in KLab launcher" ;;
      *)
        KLAB_CONTAINER_COMMAND=("$@"); return ;;
    esac
  done
}

run_container_root() {
  local image="$1"; shift
  local rt; rt="$(container_runtime)"
  klab_container_split_args "$@"
  "$rt" run --rm "${KLAB_CONTAINER_RUN_OPTS[@]}" "$image" "${KLAB_CONTAINER_COMMAND[@]}"
}

run_container_user() {
  local image="$1"; shift
  local rt; rt="$(container_runtime)"
  klab_container_split_args "$@"
  "$rt" run --rm --user "$(id -u):$(id -g)" "${KLAB_CONTAINER_RUN_OPTS[@]}" "$image" "${KLAB_CONTAINER_COMMAND[@]}"
}

validate_token() {
  local value="$1" what="$2"
  [[ "$value" =~ ^[A-Za-z0-9._+~@-]+$ ]] || die "invalid $what '$value'"
}

parse_target() {
  local target="$1" extra=""
  PROVIDER="" DISTRO_RELEASE="" KERNEL_RELEASE=""
  IFS=: read -r PROVIDER DISTRO_RELEASE KERNEL_RELEASE extra <<<"$target"
  [[ -n "$PROVIDER" && -n "$DISTRO_RELEASE" ]] || die "invalid target '$target'"
  [[ -z "$extra" ]] || die "invalid target '$target': too many ':' fields"
  validate_token "$PROVIDER" provider
  validate_token "$DISTRO_RELEASE" release
  [[ -z "$KERNEL_RELEASE" ]] || validate_token "$KERNEL_RELEASE" kernel-release
}


# ---------------------------------------------------------------------------
# Backend/capability model
# ---------------------------------------------------------------------------
backend_for_provider() {
  case "$1" in
    upstream|ubuntu|debian|fedora|centos|rhel|photon|alpine|arch|custom) printf '%s\n' linux ;;
    freebsd) printf '%s\n' freebsd ;;
    *) printf '%s\n' unknown ;;
  esac
}

target_backend() { backend_for_provider "${1%%:*}"; }

backend_capabilities() {
  case "$1" in
    linux)
      printf '%s\n' 'boot,push,exec,module-build,module-load,module-unload,module-list,crash-console,crash-vmcore'
      ;;
    freebsd)
      printf '%s\n' 'boot,push,exec,module-build,module-load,module-unload,module-list,crash-console,crash-vmcore'
      ;;
    *) printf '%s\n' 'boot,push,exec' ;;
  esac
}

target_capabilities() {
  local target="$1" backend env=""
  backend="$(target_backend "$target")"
  if [[ "$backend" != linux || "${target%%:*}" != upstream ]]; then
    parse_target "$target"
    if [[ -n "$KERNEL_RELEASE" ]]; then
      env="$(bundle_dir_for "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE")/bundle.env"
      if [[ -f "$env" ]]; then
        unset BUNDLE_CAPABILITIES BUNDLE_BACKEND
        # shellcheck disable=SC1090
        source "$env"
        [[ -n "${BUNDLE_CAPABILITIES:-}" ]] && { printf '%s\n' "$BUNDLE_CAPABILITIES"; return; }
      fi
    fi
  fi
  backend_capabilities "$backend"
}

target_has_capability() {
  local target="$1" want="$2" caps
  caps=",$(target_capabilities "$target"),"
  [[ "$caps" == *",$want,"* ]]
}

require_target_capability() {
  local target="$1" cap="$2"
  target_has_capability "$target" "$cap" || die "target '$target' does not advertise capability '$cap'"
}

cmd_capabilities() {
  (($# >= 1)) || die "usage: $0 capabilities <target> [--arch ARCH]"
  local target="$1" backend caps c arch="$ARCH"; shift
  while (($#)); do
    case "$1" in
      --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; arch="$(canonical_arch "$2")"; shift 2 ;;
      *) die "unknown capabilities option: $1" ;;
    esac
  done
  set_active_arch "$arch"
  target="$(effective_target_for_arch "$target" "$ARCH")"
  backend="$(target_backend "$target")"
  caps="$(target_capabilities "$target")"
  printf 'Target:       %s\nBackend:      %s\nTarget arch:  %s\nBuild arch:   %s\nCapabilities:\n' "$target" "$backend" "$ARCH" "$(host_arch)"
  IFS=, read -r -a _caps <<<"$caps"
  for c in "${_caps[@]}"; do [[ -n "$c" ]] && printf '  %s\n' "$c"; done
}

release_snapshot_parts() {
  local spec="$1"
  RELEASE_BASE="${spec%%@*}"
  RELEASE_SNAPSHOT=""
  if [[ "$spec" == *@* ]]; then
    RELEASE_SNAPSHOT="${spec#*@}"
    [[ "$RELEASE_SNAPSHOT" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || die "snapshot must be YYYYMMDDTHHMMSSZ: $RELEASE_SNAPSHOT"
  fi
}

bundle_dir_for() {
  local provider="$1" release="$2" krel="$3" arch="$(canonical_arch "${4:-$ARCH}")"
  printf '%s/%s/%s/%s/%s\n' "$KERNELS" "$provider" "${release//@/_}" "$arch" "$krel"
}

legacy_bundle_dir_for() {
  local provider="$1" release="$2" krel="$3"
  printf '%s/%s/%s/%s\n' "$KERNELS" "$provider" "${release//@/_}" "$krel"
}

bundle_existing_dir_for() {
  local provider="$1" release="$2" krel="$3" arch="$(canonical_arch "${4:-$ARCH}")" d
  d="$(bundle_dir_for "$provider" "$release" "$krel" "$arch")"
  [[ -f "$d/bundle.env" ]] && { printf '%s\n' "$d"; return; }
  if [[ "$arch" == x86_64 ]]; then
    d="$(legacy_bundle_dir_for "$provider" "$release" "$krel")"
    [[ -f "$d/bundle.env" ]] && { printf '%s\n' "$d"; return; }
  fi
  return 1
}

reset_bundle_toolchain_vars() {
  unset BUNDLE_TOOLCHAIN_BOUND BUNDLE_TOOLCHAIN_ID BUNDLE_TOOLCHAIN_DIR BUNDLE_DISTRO_TOOLCHAIN_ID BUNDLE_DISTRO_TOOLCHAIN_DIR BUNDLE_DISTRO_TOOLCHAIN_FILE \
        BUNDLE_TOOLCHAIN_CC_REL BUNDLE_TOOLCHAIN_CC BUNDLE_TOOLCHAIN_FAMILY \
        BUNDLE_TOOLCHAIN_VERSION BUNDLE_TOOLCHAIN_TARGET \
        BUNDLE_TOOLCHAIN_CROSS_PREFIX_REL BUNDLE_TOOLCHAIN_CROSS_PREFIX \
        BUNDLE_TOOLCHAIN_BIN_DIR BUNDLE_TOOLCHAIN_ARCHIVE_SHA256 BUNDLE_TOOLCHAIN_TREE_SHA256 \
        BUNDLE_KERNEL_COMPILER_FAMILY BUNDLE_KERNEL_COMPILER_VERSION \
        BUNDLE_KERNEL_COMPILER_BANNER BUNDLE_GUEST_BUSYBOX BUNDLE_GUEST_ARCH \
        BUNDLE_GUEST_USERSPACE_SPEC BUNDLE_GUEST_USERSPACE_KIND BUNDLE_GUEST_ROOTFS \
        BUNDLE_BUILDROOT_VERSION
}


# ---------------------------------------------------------------------------
# Toolchain detection / kernel.org crosstool resolver
# ---------------------------------------------------------------------------

download_url() {
  local url="$1" out="$2"
  if have curl; then
    curl -fL --retry 3 --connect-timeout 20 -o "$out" "$url"
  elif have wget; then
    wget -O "$out" "$url"
  else
    die "toolchain download requires curl or wget"
  fi
}


legacy_guest_busybox_path() { printf '%s/busybox-legacy-buildroot/%s/busybox\n' "$GUESTS" "$1"; }
linux24_guest_busybox_path() { printf '%s/busybox-linux24/%s/busybox\n' "$GUESTS" "$1"; }
linux22_guest_busybox_path() { printf '%s/busybox-linux22/%s/busybox\n' "$GUESTS" "$1"; }
legacy_ssh_rootfs_path() { printf '%s/legacy-ssh/linux20-glibc21-dropbear044/i386/rootfs.tar\n' "$GUESTS"; }
legacy_base64_path() { printf '%s/helpers/legacy-base64/%s/base64\n' "$GUESTS" "$1"; }
legacy_modutils_root_path() { printf '%s/legacy-modutils/debian-potato-2.3.11-13.1/i386/root\n' "$GUESTS"; }
linux20_modutils_root_path() { printf '%s/legacy-modutils/debian-slink-2.1.121-18/i386/root\n' "$GUESTS"; }

ensure_linux20_modutils() {
  local base="$GUESTS/legacy-modutils/debian-slink-2.1.121-18/i386" deb="$GUESTS/legacy-modutils/debian-slink-2.1.121-18/i386/modutils_2.1.121-18_i386.deb" root expected=43885a5969a4b55232f4834e3797d22bf0433fe02fd855e9a022e5f569b20939 got
  root="$(linux20_modutils_root_path)"
  if [[ -x "$root/sbin/insmod" && -x "$root/sbin/rmmod" ]]; then printf '%s\n' "$root"; return 0; fi
  mkdir -p "$base"
  if [[ ! -f "$deb" ]]; then
    [[ "$OFFLINE" != 1 ]] || die "offline mode: Linux 2.0 modutils artifact is missing: $deb"
    download_url 'https://archive.debian.org/debian/dists/slink/main/binary-i386/base/modutils_2.1.121-18.deb' "$deb.tmp.$$"
    mv "$deb.tmp.$$" "$deb"
  fi
  got="$(sha256sum "$deb" | awk '{print $1}')"
  [[ "$got" == "$expected" ]] || die "Linux 2.0 modutils checksum mismatch: $got"
  have dpkg-deb || die "extracting the sealed Linux 2.0 modutils package requires dpkg-deb"
  rm -rf "$root.tmp.$$"; mkdir -p "$root.tmp.$$"
  dpkg-deb -x "$deb" "$root.tmp.$$" || die "could not extract Linux 2.0 modutils"
  mv "$root.tmp.$$" "$root"
  printf '%s  %s\n' "$expected" "$(basename "$deb")" > "$base/SHA256SUMS"
  printf '%s\n' "$root"
}

ensure_linux22_modutils() {
  local base="$GUESTS/legacy-modutils/debian-potato-2.3.11-13.1/i386" deb="$GUESTS/legacy-modutils/debian-potato-2.3.11-13.1/i386/modutils_2.3.11-13.1_i386.deb" root expected=0e1e2609bf730748c59516c6968d5913bf486b2cd86a9c449aa76ef8c693e997 got
  root="$(legacy_modutils_root_path)"
  if [[ -x "$root/sbin/insmod" && -x "$root/sbin/rmmod" ]]; then printf '%s\n' "$root"; return 0; fi
  mkdir -p "$base"
  if [[ ! -f "$deb" ]]; then
    [[ "$OFFLINE" != 1 ]] || die "offline mode: Linux 2.2 modutils artifact is missing: $deb"
    download_url 'https://archive.debian.org/debian-security/dists/potato/updates/main/binary-i386/modutils_2.3.11-13.1_i386.deb' "$deb.tmp.$$"
    mv "$deb.tmp.$$" "$deb"
  fi
  got="$(sha256sum "$deb" | awk '{print $1}')"
  [[ "$got" == "$expected" ]] || die "Linux 2.2 modutils checksum mismatch: $got"
  have dpkg-deb || die "extracting the sealed Linux 2.2 modutils package requires dpkg-deb"
  rm -rf "$root.tmp.$$"; mkdir -p "$root.tmp.$$"
  dpkg-deb -x "$deb" "$root.tmp.$$" || die "could not extract Linux 2.2 modutils"
  mv "$root.tmp.$$" "$root"
  printf '%s  %s\n' "$expected" "$(basename "$deb")" > "$base/SHA256SUMS"
  printf '%s\n' "$root"
}

ensure_legacy_base64() {
  local arch="$(canonical_arch "$1")" dest source cflags=()
  dest="$(legacy_base64_path "$arch")"; source="$SELF_DIR/legacy/klab-base64.c"
  [[ -f "$source" ]] || die "legacy base64 helper source is missing: $source"
  case "$arch" in
    x86_64) cflags=(-m64) ;;
    i386) cflags=(-m32) ;;
    *) die "legacy base64 helper is not implemented for $arch" ;;
  esac
  if [[ -x "$dest" && "$dest" -nt "$source" ]]; then printf '%s\n' "$dest"; return 0; fi
  have gcc || die "building the legacy base64 helper requires gcc"
  mkdir -p "$(dirname "$dest")"
  gcc "${cflags[@]}" -Os -nostdlib -static -fno-pie -no-pie -fno-stack-protector \
    -Wl,-e,_start -Wl,--build-id=none -o "$dest.tmp.$$" "$source" || die "failed to build legacy base64 helper for $arch"
  chmod 0755 "$dest.tmp.$$"; mv "$dest.tmp.$$" "$dest"
  klab_arch_e2e_file_matches "$arch" "$(file "$dest")" || die "legacy base64 helper does not match $arch"
  sha256sum "$dest" > "$dest.sha256"
  printf '%s\n' "$dest"
}

ensure_linux22_guest_busybox() {
  local arch="$(canonical_arch "$1")" dest rootfs tmp
  [[ "$arch" == i386 ]] || die "Linux 2.0/2.2 compatibility userspace is available only for i386"
  dest="$(linux22_guest_busybox_path "$arch")"; rootfs="$(legacy_ssh_rootfs_path)"
  if validate_guest_busybox "$arch" "$dest"; then printf '%s\n' "$dest"; return 0; fi
  [[ -f "$rootfs" ]] || die "sealed Linux 2.0-compatible userspace is missing: $rootfs"
  tmp="$(mktemp)"
  tar -xOf "$rootfs" ./bin/busybox > "$tmp" || { rm -f "$tmp"; die "legacy userspace lacks /bin/busybox"; }
  chmod 0755 "$tmp"
  validate_guest_busybox "$arch" "$tmp" || { rm -f "$tmp"; die "legacy BusyBox is not a static i386 executable"; }
  mkdir -p "$(dirname "$dest")"; mv "$tmp" "$dest"; chmod 0755 "$dest"
  sha256sum "$dest" > "$dest.sha256"
  printf 'legacy-ssh:linux20-glibc21-dropbear044\n' > "$dest.source"
  printf '%s\n' "$dest"
}

ensure_linux24_guest_busybox() {
  local arch="$(canonical_arch "$1")" dest rootfs tmp
  [[ "$arch" == i386 ]] || die "Linux 2.0-2.5 userspace is currently validated only for i386"
  dest="$(linux24_guest_busybox_path "$arch")"
  if validate_guest_busybox "$arch" "$dest" && ! readelf -l "$dest" 2>/dev/null | grep -q TLS; then
    printf '%s\n' "$dest"
    return 0
  fi
  rootfs="$(ensure_buildroot_profile "$arch" minimal)" || die "could not build Linux 2.4-compatible BusyBox source rootfs"
  tmp="$(mktemp)"
  tar -xOf "$rootfs" ./bin/busybox > "$tmp" || { rm -f "$tmp"; die "Buildroot rootfs lacks /bin/busybox"; }
  chmod 0755 "$tmp"
  validate_guest_busybox "$arch" "$tmp" || { rm -f "$tmp"; die "Buildroot BusyBox is not a static $arch executable"; }
  ! readelf -l "$tmp" 2>/dev/null | grep -q TLS || { rm -f "$tmp"; die "Buildroot BusyBox contains PT_TLS and cannot run on Linux 2.4"; }
  mkdir -p "$(dirname "$dest")"
  mv "$tmp" "$dest"
  chmod 0755 "$dest"
  sha256sum "$dest" > "$dest.sha256"
  printf 'buildroot:%s/minimal\n' "$BUILDROOT_VERSION" > "$dest.source"
  printf '%s\n' "$dest"
}

ensure_legacy_guest_busybox() {
  local arch="$(canonical_arch "$1")" dest rootfs tmp
  # The standalone BusyBox 1.21 binaries crash after init on some 2.6
  # kernels. Buildroot minimal uses the same static BusyBox that is already
  # proven by the full-userspace gate, so extract and seal that binary for the
  # quick initramfs instead of maintaining a second, incompatible ABI.
  dest="$(legacy_guest_busybox_path "$arch")"
  if validate_guest_busybox "$arch" "$dest"; then printf '%s\n' "$dest"; return 0; fi
  rootfs="$(ensure_buildroot_profile "$arch" minimal)" || die "could not obtain the legacy quick-mode BusyBox source rootfs"
  tmp="$(mktemp)"
  tar -xOf "$rootfs" ./bin/busybox > "$tmp" || { rm -f "$tmp"; die "Buildroot rootfs lacks /bin/busybox"; }
  chmod 0755 "$tmp"
  validate_guest_busybox "$arch" "$tmp" || { rm -f "$tmp"; die "Buildroot BusyBox is not a static $arch executable"; }
  mkdir -p "$(dirname "$dest")"
  mv "$tmp" "$dest"
  chmod 0755 "$dest"
  sha256sum "$dest" > "$dest.sha256"
  printf 'buildroot:%s/minimal\n' "$BUILDROOT_VERSION" > "$dest.source"
  printf '%s\n' "$dest"
}

ensure_guest_busybox() {
  local arch="$(canonical_arch "$1")" dest override="" debarch page tmp filename expected actual data
  dest="$(guest_busybox_path "$arch")"
  if validate_guest_busybox "$arch" "$dest"; then printf '%s\n' "$dest"; return 0; fi
  local override_var="KLAB_BUSYBOX_${arch^^}"
  override_var="${override_var//-/_}"
  override="${!override_var:-}"
  [[ -z "$override" && "$arch" == "$(host_arch)" ]] && override="$BUSYBOX_OVERRIDE"
  if [[ -n "$override" ]]; then
    override="$(readlink -f "$override")"
    validate_guest_busybox "$arch" "$override" || die "configured BusyBox is not a static $arch executable: $override"
    mkdir -p "$(dirname "$dest")"; cp "$override" "$dest"; chmod 0755 "$dest"
    printf '%s\n' "$dest"; return 0
  fi
  # Reuse a native static BusyBox already installed on the staging host.
  if [[ "$arch" == "$(host_arch)" ]]; then
    local native="$(command -v busybox 2>/dev/null || true)"
    if [[ -n "$native" ]] && validate_guest_busybox "$arch" "$native"; then
      mkdir -p "$(dirname "$dest")"; cp "$native" "$dest"; chmod 0755 "$dest"
      printf '%s\n' "$dest"; return 0
    fi
  fi
  [[ "$OFFLINE" != 1 ]] || die "offline lab is missing architecture-matched BusyBox for $arch. Import a .klab containing guest userspace first."
  debarch="$(busybox_deb_arch "$arch" || true)"
  [[ -n "$debarch" ]] || die "no Debian busybox-static mapping for architecture '$arch'; use --userspace buildroot:minimal or provide KLAB_BUSYBOX_${arch^^}"
  tmp="$(mktemp -d)"; page="$tmp/download.html"
  say "Fetching Debian busybox-static for guest architecture $arch ($debarch)"
  download_url "https://packages.debian.org/en/${BUSYBOX_SUITE}/${debarch}/busybox-static/download" "$page" || { rm -rf "$tmp"; die "failed to download Debian busybox-static index for $arch"; }
  filename="$(grep -oE "busybox-static_[A-Za-z0-9.+~_-]+_${debarch}\\.deb" "$page" | head -n1 || true)"
  [[ -n "$filename" ]] || { rm -rf "$tmp"; die "could not discover busybox-static package for Debian $BUSYBOX_SUITE/$debarch"; }
  expected="$(grep -A8 -B2 -F "$filename" "$page" | grep -oE '[0-9a-fA-F]{64}' | head -n1 || true)"
  download_url "https://deb.debian.org/debian/pool/main/b/busybox/$filename" "$tmp/$filename" || { rm -rf "$tmp"; die "failed to download busybox-static package $filename"; }
  actual="$(sha256sum "$tmp/$filename" | awk '{print $1}')"
  if [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]]; then
    [[ "$actual" == "$expected" ]] || { rm -rf "$tmp"; die "BusyBox package checksum mismatch"; }
  fi
  mkdir -p "$tmp/root"
  if have dpkg-deb; then
    dpkg-deb -x "$tmp/$filename" "$tmp/root"
  elif have ar; then
    (cd "$tmp" && ar x "$filename")
    data="$(find "$tmp" -maxdepth 1 -type f -name 'data.tar.*' | head -n1 || true)"
    [[ -n "$data" ]] || { rm -rf "$tmp"; die "could not extract $filename (need dpkg-deb or ar+tar)"; }
    tar -xf "$data" -C "$tmp/root"
  else
    rm -rf "$tmp"; die "extracting Debian busybox-static requires dpkg-deb or ar"
  fi
  local src=""
  for src in "$tmp/root/bin/busybox" "$tmp/root/usr/bin/busybox"; do [[ -x "$src" ]] && break; done
  validate_guest_busybox "$arch" "$src" || { rm -rf "$tmp"; die "downloaded busybox-static did not contain a usable static $arch BusyBox"; }
  mkdir -p "$(dirname "$dest")"; cp "$src" "$dest"; chmod 0755 "$dest"
  {
    printf 'KLAB_GUEST_ARCH=%q\n' "$arch"
    printf 'KLAB_GUEST_SOURCE=%q\n' debian-busybox-static
    printf 'KLAB_GUEST_PACKAGE=%q\n' "$filename"
    printf 'KLAB_GUEST_PACKAGE_SHA256=%q\n' "$actual"
  } > "$(dirname "$dest")/metadata.env"
  rm -rf "$tmp"
  printf '%s\n' "$dest"
}

url_exists() {
  local url="$1"
  if have curl; then
    curl -fsIL --connect-timeout 15 "$url" >/dev/null 2>&1
  elif have wget; then
    wget -q --spider "$url" >/dev/null 2>&1
  else
    return 1
  fi
}

toolchain_target_name() {
  local a="$(canonical_arch "$1")" v=""
  v="$(arch_profile_field "$a" TOOLCHAIN_TARGET 2>/dev/null || true)"
  [[ -n "$v" ]] && { printf '%s\n' "$v"; return; }
  case "$a" in
    x86_64) printf '%s\n' x86_64-linux ;;
    i386) printf '%s\n' i386-linux ;;
    aarch64) printf '%s\n' aarch64-linux ;;
    armv7) printf '%s\n' arm-linux-gnueabi ;;
    *) die "architecture '$a' does not define TOOLCHAIN_TARGET" ;;
  esac
}

parse_compiler_banner() {
  # Prints: family<TAB>version<TAB>original-banner
  local banner="$1"
  python3 - "$banner" <<'PYBANNER'
import re,sys
s=sys.argv[1].strip()
low=s.lower()
family=''
version=''
if 'clang' in low:
    family='clang'
    m=re.search(r'clang(?: version)?[^0-9]*([0-9]+(?:\.[0-9]+){1,2})', s, re.I)
    if m: version=m.group(1)
elif 'gcc' in low or 'gnu c' in low:
    family='gcc'
    # Prefer a dotted version near GCC, then fall back to any dotted version.
    m=re.search(r'(?:gcc|gnu c)[^0-9]*([0-9]+(?:\.[0-9]+){1,2})', s, re.I)
    if not m: m=re.search(r'([0-9]+(?:\.[0-9]+){1,2})', s)
    if m: version=m.group(1)
if not family or not version:
    raise SystemExit(1)
print(f"{family}\t{version}\t{s}")
PYBANNER
}

detect_compiler_from_build_tree() {
  # Best source is the generated LINUX_COMPILER string: it is what the target
  # kernel itself uses for /proc/version.
  local build="$1" f banner parsed
  for f in \
      "$build/include/generated/compile.h" \
      "$build/include/linux/compile.h"; do
    [[ -f "$f" ]] || continue
    banner="$(sed -n 's/^#define[[:space:]]\+LINUX_COMPILER[[:space:]]\+"\(.*\)"/\1/p' "$f" | head -n1)"
    if [[ -n "$banner" ]] && parsed="$(parse_compiler_banner "$banner" 2>/dev/null)"; then
      printf '%s\n' "$parsed"
      return 0
    fi
  done
  # Some distro header packages place generated files below an arch/common tree.
  while IFS= read -r f; do
    banner="$(sed -n 's/^#define[[:space:]]\+LINUX_COMPILER[[:space:]]\+"\(.*\)"/\1/p' "$f" | head -n1)"
    if [[ -n "$banner" ]] && parsed="$(parse_compiler_banner "$banner" 2>/dev/null)"; then
      printf '%s\n' "$parsed"
      return 0
    fi
  done < <(find "$build" -maxdepth 5 -type f -name compile.h -print 2>/dev/null | head -n 20)
  return 1
}

record_upstream_compiler() {
  local build="$1" parsed family version banner
  if parsed="$(detect_compiler_from_build_tree "$build" 2>/dev/null)"; then
    IFS=$'\t' read -r family version banner <<<"$parsed"
  else
    family=gcc
    version="$(gcc -dumpfullversion -dumpversion 2>/dev/null | head -n1 || gcc -dumpversion 2>/dev/null | head -n1)"
    banner="$(gcc --version 2>/dev/null | head -n1 || true)"
  fi
  {
    printf 'KLAB_KERNEL_COMPILER_FAMILY=%q\n' "$family"
    printf 'KLAB_KERNEL_COMPILER_VERSION=%q\n' "$version"
    printf 'KLAB_KERNEL_COMPILER_BANNER=%q\n' "$banner"
  } > "$build/.klab-compiler.env"
}

crosstool_host_name() {
  case "$(canonical_arch "$1")" in
    x86_64) printf '%s\n' x86_64 ;;
    i386) printf '%s\n' i686 ;;
    aarch64) printf '%s\n' arm64 ;;
    *) return 1 ;;
  esac
}

kernelorg_versions_for_major() {
  local major="$1" hostkey tmp
  [[ "$OFFLINE" != 1 ]] || die "offline mode: cannot query kernel.org toolchains"
  hostkey="$(crosstool_host_name "$(host_arch)")" || return 1
  tmp="$(mktemp)"
  download_url "$CROSSTOOL_BASE_URL/$hostkey/" "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; return 1; }
  grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$tmp" \
    | awk -F. -v m="$major" '$1==m' \
    | sort -V -u
  rm -f "$tmp"
}

resolve_kernelorg_gcc_version() {
  local requested="$1" arch="$2" target exact_url major v chosen="" hostkey
  target="$(toolchain_target_name "$arch")"
  hostkey="$(crosstool_host_name "$(host_arch)")" || die "no kernel.org crosstool host mapping for $(host_arch)"
  # Exact version first.
  exact_url="$CROSSTOOL_BASE_URL/$hostkey/$requested/${hostkey}-gcc-$requested-nolibc-$target.tar.xz"
  if url_exists "$exact_url" || url_exists "$CROSSTOOL_BASE_URL/$hostkey/$requested/${hostkey}-gcc-$requested-nolibc_${target}.tar.xz"; then
    printf '%s\n' "$requested"
    return 0
  fi
  major="${requested%%.*}"
  local versions
  if ! versions="$(kernelorg_versions_for_major "$major")"; then
    die "could not query kernel.org crosstool index while resolving GCC $requested"
  fi
  # Do not select the newest compiler in the major.  A much newer crosstool
  # can carry newer binutils semantics that an old kernel module loader cannot
  # understand (for example x86-64 R_X86_64_PLT32 from binutils >= 2.31).
  # Prefer the first available release >= the requested compiler; if none is
  # available, fall back to the newest older release in the same major.
  chosen="$(printf '%s\n' "$versions" | awk -v req="$requested" '''
    function vnum(v, a,n,i,x) { n=split(v,a,"."); x=0; for(i=1;i<=3;i++) x=x*10000+(i<=n?a[i]:0); return x }
    BEGIN { r=vnum(req); above=""; below=""; ad=0; bd=0 }
    { x=vnum($0); if (x>=r && (above=="" || x<ad)) { above=$0; ad=x } else if (x<r && (below=="" || x>bd)) { below=$0; bd=x } }
    END { if (above!="") print above; else if (below!="") print below }
  ''')"
  [[ -n "$chosen" ]] || die "kernel.org has no GCC toolchain matching requested major $major (requested $requested)"
  say "Exact kernel compiler GCC $requested is not in kernel.org crosstool; selecting closest available GCC $chosen in the same major"
  printf '%s\n' "$chosen"
}

prune_kernelorg_toolchain_dangling_symlinks() {
  local dest="$1" id="${2:-kernel.org-toolchain}"
  [[ -d "$dest" ]] || return 0
  if find "$dest" -xtype l -print -quit 2>/dev/null | grep -q .; then
    find "$dest" -xtype l -printf '%P -> %l\n' 2>/dev/null | LC_ALL=C sort > "$dest/.klab-pruned-dangling-symlinks.txt" || true
    say "Pruning dangling optional symlinks from kernel.org toolchain $id"
    find "$dest" -xtype l -delete 2>/dev/null || true
  fi
}

fetch_kernelorg_gcc() {
  local requested="$1" arch="${2:-$ARCH}" target version id dest file base tmp sums expected actual cc hostkey
  [[ "$OFFLINE" != 1 ]] || die "offline mode: toolchain downloads are disabled"
  target="$(toolchain_target_name "$arch")"
  hostkey="$(crosstool_host_name "$(host_arch)")" || die "no kernel.org crosstool binaries are mapped for host architecture $(host_arch)"
  if ! version="$(resolve_kernelorg_gcc_version "$requested" "$arch")"; then
    return 1
  fi
  [[ -n "$version" ]] || die "toolchain resolver returned an empty GCC version"
  id="kernelorg-gcc-${version}-${hostkey}-to-${target}"
  dest="$TOOLCHAINS/$id"
  if [[ -f "$dest/.klab-resolver.env" ]]; then
    # Heal caches created by older KLab revisions before returning them.
    prune_kernelorg_toolchain_dangling_symlinks "$dest" "$id"
    printf '%s\n' "$dest"
    return 0
  fi
  mkdir -p "$TOOLCHAINS"
  base="$CROSSTOOL_BASE_URL/$hostkey/$version"
  tmp="$(mktemp -d)"
  say "Downloading kernel.org GCC $version for $target"
  download_url "$base/sha256sums.asc" "$tmp/sha256sums.asc"
  file="$(awk '{print $2}' "$tmp/sha256sums.asc" | grep -E "^${hostkey}-gcc-${version//./\.}-nolibc[-_]${target}\.tar\.xz$" | head -n1 || true)"
  [[ -n "$file" ]] || die "could not find a GCC $version archive for $target in kernel.org sha256sums.asc"
  expected="$(grep -E "[[:space:]]${file//./\.}$" "$tmp/sha256sums.asc" | awk '{print $1}' | head -n1 || true)"
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || die "could not find $file in kernel.org sha256sums.asc"
  download_url "$base/$file" "$tmp/$file"
  actual="$(sha256sum "$tmp/$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "checksum mismatch for kernel.org toolchain $file"
  rm -rf "$dest"; mkdir -p "$dest"
  tar -xJf "$tmp/$file" -C "$dest"
  # Some kernel.org crosstool archives contain optional gprofng/binutils
  # symlinks whose companion program is not shipped for every target.
  prune_kernelorg_toolchain_dangling_symlinks "$dest" "$id"
  cc="$(find "$dest" -maxdepth 6 \( -type f -o -type l \) -perm -111 -path '*/bin/*' -name '*-gcc' -print 2>/dev/null | sort | head -n1 || true)"
  [[ -n "$cc" && -x "$cc" ]] || die "downloaded kernel.org toolchain contains no usable GCC"
  {
    printf 'KLAB_TOOLCHAIN_ID=%q\n' "$id"
    printf 'KLAB_TOOLCHAIN_SOURCE=%q\n' kernel.org-crosstool
    printf 'KLAB_TOOLCHAIN_REQUESTED_VERSION=%q\n' "$requested"
    printf 'KLAB_TOOLCHAIN_VERSION=%q\n' "$version"
    printf 'KLAB_TOOLCHAIN_ARCH=%q\n' "$arch"
    printf 'KLAB_TOOLCHAIN_HOST=%q\n' "$hostkey"
    printf 'KLAB_TOOLCHAIN_TARGET=%q\n' "$target"
    printf 'KLAB_TOOLCHAIN_URL=%q\n' "$base/$file"
    printf 'KLAB_TOOLCHAIN_DOWNLOAD_SHA256=%q\n' "$actual"
    printf 'KLAB_TOOLCHAIN_CC=%q\n' "$cc"
  } > "$dest/.klab-resolver.env"
  cp "$tmp/sha256sums.asc" "$dest/.kernelorg-sha256sums.asc"
  rm -rf "$tmp"
  printf '%s\n' "$dest"
}

get_target_compiler_requirement() {
  # Prints family<TAB>version<TAB>banner. The version is the compiler that
  # actually built the cached target whenever that metadata is available.
  local target="$1" profile="${2:-normal}" provider raw build parsed family version banner envfile
  provider="${target%%:*}"
  if [[ "$provider" == upstream ]]; then
    raw="${target#upstream:}"
    build="$(resolve_upstream_build_dir "$raw" "$profile" "$ARCH" 2>/dev/null || true)"
    if [[ -z "$build" ]]; then
      local idir; idir="$(imported_upstream_dir "$raw" "$profile" "$ARCH")"
      if [[ -f "$idir/bundle.env" ]]; then
        reset_bundle_toolchain_vars; unset BUNDLE_KERNEL_COMPILER_FAMILY BUNDLE_KERNEL_COMPILER_VERSION BUNDLE_KERNEL_COMPILER_BANNER
        # shellcheck disable=SC1090
        source "$idir/bundle.env"
        if [[ -n "${BUNDLE_KERNEL_COMPILER_FAMILY:-}" && -n "${BUNDLE_KERNEL_COMPILER_VERSION:-}" ]]; then
          printf '%s\t%s\t%s\n' "$BUNDLE_KERNEL_COMPILER_FAMILY" "$BUNDLE_KERNEL_COMPILER_VERSION" "${BUNDLE_KERNEL_COMPILER_BANNER:-}"
          return 0
        fi
        build="${BUNDLE_BUILD_DIR:-}"
      fi
    fi
    [[ -n "$build" && -d "$build" ]] || die "no cached upstream build for $target/$ARCH/$profile; build it first"
    envfile="$build/.klab-compiler.env"
    if [[ -f "$envfile" ]]; then
      unset KLAB_KERNEL_COMPILER_FAMILY KLAB_KERNEL_COMPILER_VERSION KLAB_KERNEL_COMPILER_BANNER
      # shellcheck disable=SC1090
      source "$envfile"
      printf '%s\t%s\t%s\n' "$KLAB_KERNEL_COMPILER_FAMILY" "$KLAB_KERNEL_COMPILER_VERSION" "${KLAB_KERNEL_COMPILER_BANNER:-}"
      return 0
    fi
    detect_compiler_from_build_tree "$build" || die "could not determine compiler used for cached upstream build $target"
    return 0
  fi
  bundle_load "$target"
  if [[ -n "${BUNDLE_KERNEL_COMPILER_FAMILY:-}" && -n "${BUNDLE_KERNEL_COMPILER_VERSION:-}" ]]; then
    printf '%s\t%s\t%s\n' "$BUNDLE_KERNEL_COMPILER_FAMILY" "$BUNDLE_KERNEL_COMPILER_VERSION" "${BUNDLE_KERNEL_COMPILER_BANNER:-}"
    return 0
  fi
  parsed="$(detect_compiler_from_build_tree "$BUNDLE_BUILD_DIR" 2>/dev/null || true)"
  [[ -n "$parsed" ]] || die "could not determine which compiler built $target from its header/build package; use --include-toolchain manually"
  printf '%s\n' "$parsed"
}

toolchain_arch_matches() {
  local candidate wanted
  candidate="$(canonical_arch "$1")"
  wanted="$(canonical_arch "$2")"
  [[ "$candidate" == "$wanted" ]] && return 0
  case "$candidate:$wanted" in
    mips:mipsel|mipsel:mips|mips64:mips64el|mips64el:mips64) return 0 ;;
  esac
  return 1
}

ensure_toolchain_for_target() {
  local target="$1" profile="${2:-normal}" req family version banner dir
  req="$(get_target_compiler_requirement "$target" "$profile")"
  IFS=$'\t' read -r family version banner <<<"$req"
  [[ "$family" == gcc ]] || die "automatic toolchain fetching currently supports GCC targets only; target reports $family $version"
  dir=""
  local candidate
  for candidate in "$TOOLCHAINS"/*; do
    [[ -f "$candidate/.klab-resolver.env" ]] || continue
    unset KLAB_TOOLCHAIN_REQUESTED_VERSION KLAB_TOOLCHAIN_VERSION KLAB_TOOLCHAIN_ARCH
    source "$candidate/.klab-resolver.env"
    [[ "${KLAB_TOOLCHAIN_REQUESTED_VERSION:-${KLAB_TOOLCHAIN_VERSION:-}}" == "$version" ]] || continue
    toolchain_arch_matches "${KLAB_TOOLCHAIN_ARCH:-$ARCH}" "$ARCH" || continue
    dir="$candidate"; break
  done
  [[ -n "$dir" ]] || dir="$(fetch_kernelorg_gcc "$version" "$ARCH")"
  # Record why this cached toolchain was chosen for auditability.
  {
    printf 'KLAB_RESOLVED_FOR_TARGET=%q\n' "$target"
    printf 'KLAB_RESOLVED_FOR_PROFILE=%q\n' "$profile"
    printf 'KLAB_TARGET_COMPILER_FAMILY=%q\n' "$family"
    printf 'KLAB_TARGET_COMPILER_VERSION=%q\n' "$version"
    printf 'KLAB_TARGET_COMPILER_BANNER=%q\n' "$banner"
  } > "$dir/.klab-last-resolution.env"
  printf '%s\n' "$dir"
}

cmd_toolchain() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    detect)
      (($# >= 1 && $# <= 2)) || die "toolchain detect TARGET [profile]"
      get_target_compiler_requirement "$1" "${2:-normal}"
      ;;
    ensure)
      (($# >= 1 && $# <= 2)) || die "toolchain ensure TARGET [profile]"
      ensure_toolchain_for_target "$1" "${2:-normal}"
      ;;
    distro-capture)
      (($# >= 1 && $# <= 3)) || die "toolchain distro-capture provider:release[:kernel] [--output FILE.klabdistrotoolchain]"
      local dt_target="$1" dt_out="" dt_provider dt_release dt_kernel="" dt_bundle="" dt_tmp dt_line dt_req="" dt_family="" dt_version="" dt_banner=""
      shift
      if (($#)); then [[ "$1" == --output && $# == 2 ]] || die "toolchain distro-capture accepts only --output FILE"; dt_out="$2"; fi
      dt_provider="${dt_target%%:*}"; local dt_rest="${dt_target#*:}"; [[ "$dt_rest" != "$dt_target" ]] || die "distro-capture target needs provider:release[:kernel]"
      dt_release="${dt_rest%%:*}"
      [[ "$dt_rest" != *:* ]] || dt_kernel="${dt_rest#*:}"
      case "$dt_provider" in ubuntu|debian|fedora|centos|rhel|alpine) ;; *) die "distro-native toolchain capture is not implemented for provider $dt_provider";; esac
      [[ "$OFFLINE" != 1 ]] || die "offline mode: distro toolchain capture requires a staging repository or configured mirror"
      [[ -x "$DISTRO_TOOLCHAIN_BIN" ]] || die "distro toolchain artifact helper missing: $DISTRO_TOOLCHAIN_BIN"
      if [[ "$dt_provider" == fedora ]]; then
        [[ -n "$dt_kernel" ]] || die "Fedora distro-toolchain capture requires an exact target: fedora:release:kernel; the kernel's Koji buildroot is the compiler source of truth"
        cmd_fetch "$dt_target" >/dev/null
        parse_target "$dt_target"
        dt_bundle="$(bundle_existing_dir_for "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$ARCH")"
        [[ -s "$dt_bundle/koji-buildroot.json" ]] || die "Fedora target lacks Koji buildroot provenance; set KLAB_REFETCH=1 and fetch it again"
      fi
      dt_tmp="$(mktemp -d)"; trap 'rm -rf "$dt_tmp"' RETURN
      if [[ -n "$dt_kernel" ]]; then
        dt_req="$(get_target_compiler_requirement "$dt_target" 2>/dev/null || true)"
        if [[ -n "$dt_req" ]]; then IFS=$'\t' read -r dt_family dt_version dt_banner <<<"$dt_req"; fi
      fi
      say "Capturing distribution-native GCC/binutils closure for $dt_provider:$dt_release [$ARCH]${dt_version:+; target compiler $dt_family $dt_version}"
      KLAB_PROVIDER_TARGET_BUNDLE="$dt_bundle" KLAB_PROVIDER_KERNEL_RELEASE="$dt_kernel" \
        klab_provider_capture_toolchain "$dt_provider" "$dt_release" "$dt_tmp" "$ARCH" "$dt_version"
      [[ -n "$dt_out" ]] || dt_out="$EXPORTS/distro-toolchain-${dt_provider}-${dt_release}-${ARCH}.klabdistrotoolchain"
      mkdir -p "$(dirname "$dt_out")"
      local dt_prov=()
      [[ ! -f "$dt_tmp/provenance.json" ]] || dt_prov=(--provenance "$dt_tmp/provenance.json")
      dt_line="$($DISTRO_TOOLCHAIN_BIN create --packages "$dt_tmp/packages" --inventory "$dt_tmp/packages.tsv" --compiler-json "$dt_tmp/compiler.json" "${dt_prov[@]}" --provider "$dt_provider" --release "$dt_release" --arch "$ARCH" -o "$dt_out")"
      printf '%s\n' "$dt_line"
      rm -rf "$dt_tmp"; trap - RETURN
      ;;
    fetch)
      (($# == 1)) || die "toolchain fetch gcc:<version-or-major>[:arch]"
      local fam ver arch extra
      IFS=: read -r fam ver arch extra <<<"$1"
      [[ "$fam" == gcc && -n "$ver" && -z "$extra" ]] || die "toolchain fetch syntax: gcc:<version-or-major>[:arch]"
      arch="${arch:-$ARCH}"
      # A major-only request resolves to newest available release in that major.
      if [[ "$ver" != *.* ]]; then
        local last="" x
        while IFS= read -r x; do last="$x"; done < <(kernelorg_versions_for_major "$ver")
        [[ -n "$last" ]] || die "no kernel.org GCC releases found for major $ver"
        ver="$last"
      fi
      fetch_kernelorg_gcc "$ver" "$arch"
      ;;
    list)
      mkdir -p "$TOOLCHAINS"
      local d
      for d in "$TOOLCHAINS"/*; do
        [[ -d "$d" ]] || continue
        if [[ -f "$d/.klab-resolver.env" ]]; then
          unset KLAB_TOOLCHAIN_ID KLAB_TOOLCHAIN_SOURCE KLAB_TOOLCHAIN_VERSION KLAB_TOOLCHAIN_TARGET
          # shellcheck disable=SC1090
          source "$d/.klab-resolver.env"
          printf '%-42s  %-8s  %-18s  %s\n' "${KLAB_TOOLCHAIN_ID:-$(basename "$d")}" "${KLAB_TOOLCHAIN_VERSION:-?}" "${KLAB_TOOLCHAIN_TARGET:-?}" "${KLAB_TOOLCHAIN_SOURCE:-local}"
        else
          printf '%s\n' "$(basename "$d")"
        fi
      done
      ;;
    *) die "toolchain subcommands: detect, ensure, fetch, list" ;;
  esac
}

compiler_identity() {
  local cc="$1" base
  base="$(basename "$cc")"
  KLAB_COMPILER_FAMILY=""
  KLAB_COMPILER_VERSION=""
  KLAB_COMPILER_TARGET=""
  case "$base" in
    *gcc*)
      KLAB_COMPILER_FAMILY=gcc
      KLAB_COMPILER_VERSION="$($cc -dumpfullversion -dumpversion 2>/dev/null | head -n1)"
      [[ -n "$KLAB_COMPILER_VERSION" ]] || KLAB_COMPILER_VERSION="$($cc -dumpversion 2>/dev/null | head -n1)"
      KLAB_COMPILER_TARGET="$($cc -dumpmachine 2>/dev/null | head -n1 || true)"
      ;;
    clang*)
      KLAB_COMPILER_FAMILY=clang
      KLAB_COMPILER_VERSION="$($cc --version 2>/dev/null | sed -n '1s/.*clang version \([^ ]*\).*/\1/p')"
      [[ -n "$KLAB_COMPILER_VERSION" ]] || KLAB_COMPILER_VERSION="$($cc --version 2>/dev/null | head -n1)"
      KLAB_COMPILER_TARGET="$($cc -dumpmachine 2>/dev/null | head -n1 || true)"
      ;;
    *) die "cannot identify compiler family for $cc" ;;
  esac
}

toolchain_runtime_library_path() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  # Sealed compiler archives may carry private loader dependencies outside the
  # runtime-libs subtree (notably Debian binutils libbfd/libopcodes). Expose
  # only compiler/binutils libraries, never a captured libc or dynamic loader.
  find "$root"     \( -type f -o -type l \)     \( -name 'libbfd*.so*' -o -name 'libopcodes*.so*' -o        -name 'libmpfr*.so*' -o -name 'libmpc*.so*' -o        -name 'libgmp*.so*' -o -name 'libgcc_s.so*' -o        -name 'libstdc++.so*' \) -printf '%h\n' 2>/dev/null |     LC_ALL=C sort -u | paste -sd: -
}

prepare_bound_toolchain() {
  KLAB_TC_PATH="$PATH"
  KLAB_TC_LIBRARY_PATH=""
  KLAB_TC_MAKE_ARGS=()
  [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 ]] || return 0

  local cc="${BUNDLE_TOOLCHAIN_CC:-}" overridden=0 marker=""
  [[ -n "${BUNDLE_TOOLCHAIN_DIR:-}" ]] || die "bundle declares a bound toolchain but has no toolchain directory"
  [[ -n "${BUNDLE_TOOLCHAIN_CC:-}" ]] || die "bundle declares a bound toolchain but has no compiler path"

  if [[ -n "$TOOLCHAIN_OVERRIDE_CC" ]]; then
    [[ "$ALLOW_TOOLCHAIN_OVERRIDE" == 1 ]] || die "target is bound to toolchain '${BUNDLE_TOOLCHAIN_ID:-unknown}'. Refusing KLAB_CC override; set KLAB_ALLOW_TOOLCHAIN_OVERRIDE=1 only if you intentionally want a non-reproducible override"
    cc="$TOOLCHAIN_OVERRIDE_CC"
    overridden=1
    say "WARNING: overriding bound toolchain ${BUNDLE_TOOLCHAIN_ID:-unknown} with $cc"
  fi
  [[ -x "$cc" ]] || die "selected compiler is not executable: $cc"

  if (( overridden == 0 )); then
    marker="$BUNDLE_TOOLCHAIN_DIR/.klab-toolchain.sha256"
    [[ -f "$marker" ]] || die "bound toolchain integrity marker missing: $marker"
    [[ "$(cat "$marker")" == "${BUNDLE_TOOLCHAIN_ARCHIVE_SHA256:-}" ]] || die "bound toolchain integrity marker does not match bundle binding"
  fi

  if (( overridden == 0 )) && [[ -n "${BUNDLE_TOOLCHAIN_TREE_SHA256:-}" || -f "$BUNDLE_TOOLCHAIN_DIR/.klab-toolchain-boundary.json" ]]; then
    local __tc_guard=(verify --root "$BUNDLE_TOOLCHAIN_DIR" --cc "${BUNDLE_TOOLCHAIN_CC_REL:-${cc#"$BUNDLE_TOOLCHAIN_DIR"/}}" --family "${BUNDLE_TOOLCHAIN_FAMILY:-gcc}")
    [[ -n "${BUNDLE_TOOLCHAIN_TREE_SHA256:-}" ]] && __tc_guard+=(--tree-sha256 "$BUNDLE_TOOLCHAIN_TREE_SHA256")
    [[ -n "${BUNDLE_TOOLCHAIN_VERSION:-}" ]] && __tc_guard+=(--version "$BUNDLE_TOOLCHAIN_VERSION")
    [[ -n "${BUNDLE_TOOLCHAIN_TARGET:-}" ]] && __tc_guard+=(--target "$BUNDLE_TOOLCHAIN_TARGET")
    "$TOOLCHAIN_BOUNDARY_BIN" "${__tc_guard[@]}" >/dev/null
  fi

  compiler_identity "$cc"
  if (( overridden == 0 )); then
    [[ -z "${BUNDLE_TOOLCHAIN_FAMILY:-}" || "$KLAB_COMPILER_FAMILY" == "$BUNDLE_TOOLCHAIN_FAMILY" ]] || die "bound compiler family changed: expected $BUNDLE_TOOLCHAIN_FAMILY, got $KLAB_COMPILER_FAMILY"
    [[ -z "${BUNDLE_TOOLCHAIN_VERSION:-}" || "$KLAB_COMPILER_VERSION" == "$BUNDLE_TOOLCHAIN_VERSION" ]] || die "bound compiler version changed: expected $BUNDLE_TOOLCHAIN_VERSION, got $KLAB_COMPILER_VERSION"
    [[ -z "${BUNDLE_TOOLCHAIN_TARGET:-}" || "$BUNDLE_TOOLCHAIN_TARGET" == unknown || "$KLAB_COMPILER_TARGET" == "$BUNDLE_TOOLCHAIN_TARGET" ]] || die "bound compiler target changed: expected $BUNDLE_TOOLCHAIN_TARGET, got $KLAB_COMPILER_TARGET"
  fi

  # Native archived compilers are absolute paths. Keep their vintage binutils
  # out of PATH so modern HOSTCC does not feed CET instructions to an old as.
  # Cross compilers still need their prefixed sibling tools in PATH.
  if [[ -n "${BUNDLE_TOOLCHAIN_BIN_DIR:-}" && -n "${BUNDLE_TOOLCHAIN_CROSS_PREFIX:-}" ]]; then
    KLAB_TC_PATH="$BUNDLE_TOOLCHAIN_BIN_DIR:$PATH"
  fi
  KLAB_TC_LIBRARY_PATH="$(toolchain_runtime_library_path "$BUNDLE_TOOLCHAIN_DIR")"
  KLAB_TC_MAKE_ARGS+=("CC=$cc" "HOSTCC=$(command -v gcc)" "HOSTCFLAGS=-fno-pie -no-pie -fcf-protection=none -fgnu89-inline" "HOSTLDFLAGS=-no-pie")
  if (( overridden == 0 )) && [[ -n "${BUNDLE_TOOLCHAIN_CROSS_PREFIX:-}" ]]; then
    local bound_cross_prefix="$BUNDLE_TOOLCHAIN_CROSS_PREFIX"
    # Some archived native Debian compilers report a target-prefixed resolver
    # even though their sealed binutils are installed as bin/{as,ld,...}.
    # Preserve CROSS_COMPILE semantics and old Makefile flag appends by falling
    # back to that complete wrapper prefix instead of assigning tools one by one.
    if [[ ! -x "${bound_cross_prefix}ld" && -x "$BUNDLE_TOOLCHAIN_DIR/bin/ld" ]]; then
      bound_cross_prefix="$BUNDLE_TOOLCHAIN_DIR/bin/"
    fi
    KLAB_TC_MAKE_ARGS+=("CROSS_COMPILE=$bound_cross_prefix")
  fi
  say "Using bound toolchain ${BUNDLE_TOOLCHAIN_ID:-unknown}: $KLAB_COMPILER_FAMILY $KLAB_COMPILER_VERSION ($KLAB_COMPILER_TARGET)"
}

bound_make() {
  PATH="$KLAB_TC_PATH" LD_LIBRARY_PATH="${KLAB_TC_LIBRARY_PATH:-${LD_LIBRARY_PATH:-}}" make "${KLAB_TC_MAKE_ARGS[@]}" "$@"
}

bundle_load() {
  local target="$1" bundle
  parse_target "$target"
  [[ -n "$KERNEL_RELEASE" ]] || die "target needs a kernel release: $target"
  bundle="$(bundle_existing_dir_for "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$ARCH" 2>/dev/null || true)"
  [[ -n "$bundle" && -f "$bundle/bundle.env" ]] || die "bundle is not fetched for $target [$ARCH]\nPrepare/import that architecture first."
  reset_bundle_toolchain_vars
  unset BUNDLE_BACKEND BUNDLE_TARGET_ID BUNDLE_CAPABILITIES BUNDLE_BOOT_TYPE BUNDLE_ARCH BUNDLE_OS_RELEASE \
        BUNDLE_DISK_IMAGE BUNDLE_SEED_ISO BUNDLE_SOURCE_ISO BUNDLE_SOURCE_ARCHIVE
  # shellcheck disable=SC1090
  source "$bundle/bundle.env"
  if [[ -n "${BUNDLE_ARCH:-}" ]]; then
    local loaded_arch; loaded_arch="$(canonical_arch "$BUNDLE_ARCH")"
    [[ "$loaded_arch" == "$ARCH" ]] || die "target bundle architecture $loaded_arch does not match requested architecture $ARCH"
  fi
}

provider_image() {
  local provider="$1" release="$2"
  release_snapshot_parts "$release"
  case "$provider" in
    ubuntu) printf 'ubuntu:%s\n' "$RELEASE_BASE" ;;
    debian) printf 'debian:%s-slim\n' "$RELEASE_BASE" ;;
    fedora) printf 'fedora:%s\n' "$RELEASE_BASE" ;;
    alpine) printf 'alpine:%s\n' "$RELEASE_BASE" ;;
    arch) printf 'archlinux:base\n' ;;
    centos) printf 'quay.io/centos/centos:%s\n' "$RELEASE_BASE" ;;
    rhel)
      [[ -n "${KLAB_RHEL_IMAGE:-}" ]] || return 1
      printf '%s\n' "$KLAB_RHEL_IMAGE"
      ;;
    *) return 1 ;;
  esac
}

apt_snapshot_setup_script() {
  local provider="$1" release="$2"
  release_snapshot_parts "$release"
  if [[ -z "$RELEASE_SNAPSHOT" ]]; then
    printf '%s\n' 'apt-get update -qq'
    return
  fi

  if [[ "$provider" == ubuntu ]]; then
    cat <<EOS
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq apt ca-certificates >/dev/null
if [ -f /etc/apt/sources.list ]; then
  sed -i -E '/^[[:space:]]*deb / { /snapshot=/! s#^deb #deb [snapshot=yes] #; }' /etc/apt/sources.list || true
fi
apt-get update -qq --snapshot '$RELEASE_SNAPSHOT'
EOS
  else
    local suite="$RELEASE_BASE" security_suite components='main contrib non-free'
    case "$suite" in wheezy|jessie|stretch|buster) security_suite="$suite/updates";; *) security_suite="$suite-security";; esac
    case "$suite" in bookworm|trixie|forky|sid) components+=' non-free-firmware';; esac
    cat <<EOS
# Slim Debian images may omit the CA bundle. Bootstrap it from the image's
# authenticated default repository before switching to the pinned snapshot.
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates >/dev/null
cat >/etc/apt/sources.list <<'EOSOURCES'
deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/$RELEASE_SNAPSHOT/ $suite $components
deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/$RELEASE_SNAPSHOT/ $suite-updates $components
deb [check-valid-until=no] https://snapshot.debian.org/archive/debian-security/$RELEASE_SNAPSHOT/ $security_suite $components
EOSOURCES
apt-get -o Acquire::Check-Valid-Until=false update -qq
EOS
  fi
}


# ---------------------------------------------------------------------------
# FreeBSD provider/backend (x86_64 + aarch64)
# ---------------------------------------------------------------------------
iso_builder() {
  if have xorriso; then printf '%s\n' xorriso
  elif have genisoimage; then printf '%s\n' genisoimage
  elif have mkisofs; then printf '%s\n' mkisofs
  elif [[ -x "$KLAB_ARTIFACTS/host-tools/genisoimage/usr/bin/genisoimage" ]]; then
    printf '%s\n' "$KLAB_ARTIFACTS/host-tools/genisoimage/usr/bin/genisoimage"
  else return 1
  fi
}

make_iso_dir() {
  local src="$1" out="$2" label="$3" tool
  tool="$(iso_builder)" || die "FreeBSD preparation requires xorriso, genisoimage, or mkisofs on the staging machine"
  rm -f "$out"
  case "${tool##*/}" in
    xorriso) "$tool" -as mkisofs -quiet -R -V "$label" -o "$out" "$src" >/dev/null ;;
    genisoimage|mkisofs) "$tool" -quiet -R -V "$label" -o "$out" "$src" >/dev/null ;;
    *) die "unsupported ISO builder selected: $tool" ;;
  esac
  [[ -s "$out" ]] || die "ISO builder did not create $out"
}

write_freebsd_agent() {
  local out="$1" tty="${2:-/dev/ttyu1}"
  cat > "$out" <<'EOF_KLAB_FBSD_AGENT'
#!/bin/sh
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export PATH
TTY=__KLAB_TTY__
n=0
while [ ! -c "$TTY" ] && [ $n -lt 600 ]; do
    for candidate in /dev/ttyV*; do
        if [ -c "$candidate" ]; then TTY="$candidate"; break; fi
    done
    [ -c "$TTY" ] || { n=$((n+1)); sleep 0.05; }
done
[ -c "$TTY" ] || exit 1
exec 3<>"$TTY"
stty -f "$TTY" 115200 raw -echo 2>/dev/null || true
printf 'READY %s\n' "$(uname -r)" >&3
put_token= put_path= put_mode=
while :; do
    if ! IFS= read -r line <&3; then
        exec 3>&-
        sleep 0.05
        until exec 3<>"$TTY"; do
            sleep 0.05
        done
        printf 'READY %s\n' "$(uname -r)" >&3
        continue
    fi
    set -- $line
    verb="${1:-}"
    case "$verb" in
      PING) printf 'PONG %s\n' "${2:-0}" >&3 ;;
      EXEC)
        token="${2:-}"; encoded="${3:-}"
        cmdfile="/tmp/klab.cmd.$token"; outfile="/tmp/klab.out.$token"
        if ! printf '%s' "$encoded" | base64 -d > "$cmdfile" 2>/dev/null; then
            printf 'BEGIN %s 125\nEND %s 125\n' "$token" "$token" >&3; continue
        fi
        /bin/sh "$cmdfile" >"$outfile" 2>&1; rc=$?
        printf 'BEGIN %s %s\n' "$token" "$rc" >&3
        base64 "$outfile" 2>/dev/null | while IFS= read -r b64; do printf 'DATA %s %s\n' "$token" "$b64" >&3; done
        printf 'END %s %s\n' "$token" "$rc" >&3
        rm -f "$cmdfile" "$outfile"
        ;;
      PUT)
        token="${2:-}"; path64="${3:-}"; mode="${4:-0644}"
        path="$(printf '%s' "$path64" | base64 -d 2>/dev/null || true)"
        case "$path" in /*) ;; *) printf 'PUTERR %s invalid-path\n' "$token" >&3; put_token=; continue ;; esac
        mkdir -p "$(dirname "$path")"
        : > "$path" || { printf 'PUTERR %s create-failed\n' "$token" >&3; put_token=; continue; }
        put_token="$token"; put_path="$path"; put_mode="$mode"
        ;;
      DATA)
        token="${2:-}"; seq="${3:-}"; data="${4:-}"
        if [ -n "$put_token" ] && [ "$token" = "$put_token" ]; then
            if printf '%s' "$data" | base64 -d >> "$put_path" 2>/dev/null; then
                printf 'DATAOK %s %s\n' "$token" "$seq" >&3
            else
                printf 'DATAERR %s %s\n' "$token" "$seq" >&3
            fi
        fi
        ;;
      ENDPUT)
        token="${2:-}"
        if [ -n "$put_token" ] && [ "$token" = "$put_token" ]; then
            chmod "$put_mode" "$put_path" 2>/dev/null || true
            size="$(wc -c < "$put_path" 2>/dev/null || echo 0)"
            printf 'PUTOK %s %s\n' "$token" "$size" >&3
        else printf 'PUTERR %s no-active-put\n' "$token" >&3; fi
        put_token=; put_path=; put_mode=
        ;;
      GET)
        token="${2:-}"; path64="${3:-}"
        path="$(printf '%s' "$path64" | base64 -d 2>/dev/null || true)"
        if [ ! -f "$path" ]; then printf 'GETERR %s not-found\n' "$token" >&3; continue; fi
        size="$(wc -c < "$path" 2>/dev/null || echo 0)"
        printf 'GETBEGIN %s %s\n' "$token" "$size" >&3
        base64 "$path" 2>/dev/null | while IFS= read -r b64; do printf 'GETDATA %s %s\n' "$token" "$b64" >&3; done
        printf 'GETEND %s %s\n' "$token" "$size" >&3
        ;;
      *) printf 'ERROR unknown-command\n' >&3 ;;
    esac
done
EOF_KLAB_FBSD_AGENT
  sed -i "s|^TTY=__KLAB_TTY__$|TTY=$tty|" "$out"
  chmod +x "$out"
}

make_freebsd_seed_iso() {
  local bundle="$1" arch="${2:-x86_64}" authorized_key="${3:-}" tmp agent tty=/dev/ttyu1
  [[ "$arch" == aarch64 ]] && tty=/dev/ttyV0.0
  tmp="$(mktemp -d)"; agent="$tmp/klab-agent.sh"
  write_freebsd_agent "$agent" "$tty"
  cat > "$tmp/meta-data" <<'EOF_META'
instance-id: kernel-lab
local-hostname: kernel-lab
EOF_META
  cat > "$tmp/user-data" <<'EOF_USER_HEAD'
#!/bin/sh
set -eu
mkdir -p /usr/local/sbin /usr/local/etc/rc.d /var/log
cat > /usr/local/sbin/klab-agent <<'EOF_AGENT'
EOF_USER_HEAD
  cat "$agent" >> "$tmp/user-data"
  printf '%s\n' EOF_AGENT >> "$tmp/user-data"
  if [[ -n "$authorized_key" ]]; then
    cat >> "$tmp/user-data" <<'EOF_SSH_HEAD'
mkdir -p /root/.ssh
chmod 0700 /root/.ssh
cat > /root/.ssh/authorized_keys <<'EOF_AUTHORIZED_KEY'
EOF_SSH_HEAD
    cat "$authorized_key" >> "$tmp/user-data"
    cat >> "$tmp/user-data" <<'EOF_SSH_TAIL'
EOF_AUTHORIZED_KEY
chmod 0600 /root/.ssh/authorized_keys
grep -q '^PermitRootLogin without-password$' /etc/ssh/sshd_config || echo 'PermitRootLogin without-password' >> /etc/ssh/sshd_config
grep -q '^PasswordAuthentication no$' /etc/ssh/sshd_config || echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
EOF_SSH_TAIL
  fi
  cat >> "$tmp/user-data" <<'EOF_USER_TAIL'
chmod 0755 /usr/local/sbin/klab-agent
cat > /usr/local/etc/rc.d/klab_agent <<'EOF_RC'
#!/bin/sh
# PROVIDE: klab_agent
# REQUIRE: LOGIN
# KEYWORD: shutdown
. /etc/rc.subr
name=klab_agent
rcvar=klab_agent_enable
command=/usr/sbin/daemon
command_args="-f -o /var/log/klab-agent.log /usr/local/sbin/klab-agent"
load_rc_config "$name"
: ${klab_agent_enable:=NO}
run_rc_command "$1"
EOF_RC
chmod 0755 /usr/local/etc/rc.d/klab_agent
sysrc klab_agent_enable=YES >/dev/null
# Ensure later boots always expose a serial console; cloud VM images normally do already.
grep -q '^console="comconsole"' /boot/loader.conf 2>/dev/null || echo 'console="comconsole"' >> /boot/loader.conf
# Start immediately on this first boot; no guest network is required by kernel-lab.
/usr/sbin/daemon -f -o /var/log/klab-agent.log /usr/local/sbin/klab-agent || true
EOF_USER_TAIL
  make_iso_dir "$tmp" "$bundle/cidata.iso" cidata
  rm -rf "$tmp"
}

freebsd_verify_manifest_file() {
  local manifest="$1" file="$2" path="$3" expected actual
  expected="$(awk -F '\t' -v f="$file" '$1==f {print $2; exit}' "$manifest")"
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || die "FreeBSD MANIFEST has no SHA-256 for $file"
  actual="$(sha256sum "$path" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "FreeBSD checksum mismatch for $file"
}

freebsd_verify_vm_checksum() {
  local checks="$1" file="$2" path="$3" expected actual
  expected="$(sed -n -E "s/^SHA256 \\(${file//./\\.}\\) = ([0-9a-fA-F]{64})$/\\1/p" "$checks" | head -n1)"
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || die "FreeBSD VM checksum file has no SHA-256 for $file"
  actual="$(sha256sum "$path" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || die "FreeBSD VM image checksum mismatch for $file"
}

fetch_freebsd_bundle() {
  local release="$1" provider_arch="$2" bundle="$3" arch vmarch distarch distsub vmtag vm_base dist_base tmp vmfile
  arch="$(canonical_arch "$provider_arch")"
  case "$provider_arch" in amd64) arch=x86_64 ;; arm64|aarch64) arch=aarch64 ;; esac
  case "$arch" in
    x86_64) vmarch=amd64; distarch=amd64; distsub=amd64; vmtag=amd64 ;;
    aarch64) vmarch=aarch64; distarch=arm64; distsub=aarch64; vmtag=arm64-aarch64 ;;
    *) die "FreeBSD automated provider currently supports x86_64 and aarch64; requested $arch" ;;
  esac
  have xz || die "FreeBSD provider requires xz"
  vm_base="$FREEBSD_DOWNLOAD_BASE/releases/VM-IMAGES/$release/$vmarch/Latest"
  dist_base="$FREEBSD_DOWNLOAD_BASE/releases/$distarch/$distsub/$release"
  tmp="$(mktemp -d)"; mkdir -p "$bundle/packages"
  say "Discovering official FreeBSD $release $arch VM image"
  download_url "$vm_base/" "$tmp/index.html"
  vmfile="$(grep -oE "FreeBSD-${release}-${vmtag}-BASIC-(CLOUDINIT|CI)-ufs\\.qcow2\\.xz" "$tmp/index.html" | head -n1 || true)"
  [[ -n "$vmfile" ]] || die "no BASIC-CLOUDINIT/BASIC-CI UFS qcow2 image found for FreeBSD $release $arch"
  say "Downloading FreeBSD VM image, source set, and manifests"
  download_url "$vm_base/$vmfile" "$bundle/packages/$vmfile"
  download_url "$vm_base/CHECKSUM.SHA256" "$bundle/packages/CHECKSUM.SHA256"
  freebsd_verify_vm_checksum "$bundle/packages/CHECKSUM.SHA256" "$vmfile" "$bundle/packages/$vmfile"
  download_url "$dist_base/MANIFEST" "$bundle/packages/MANIFEST"
  download_url "$dist_base/src.txz" "$bundle/packages/src.txz"
  freebsd_verify_manifest_file "$bundle/packages/MANIFEST" src.txz "$bundle/packages/src.txz"
  say "Decompressing FreeBSD qcow2 base"
  xz -dc "$bundle/packages/$vmfile" > "$bundle/freebsd-base.qcow2"
  local isodir="$tmp/source-iso"
  mkdir -p "$isodir"; cp "$bundle/packages/src.txz" "$isodir/src.txz"; cp "$bundle/packages/MANIFEST" "$isodir/MANIFEST"
  make_iso_dir "$isodir" "$bundle/source.iso" KLABSRC
  make_freebsd_seed_iso "$bundle" "$arch"
  local caps; caps="$(backend_capabilities freebsd)"
  cat > "$bundle/bundle.env" <<EOF_FBSD_ENV
BUNDLE_PROVIDER=freebsd
BUNDLE_BACKEND=freebsd
BUNDLE_TARGET_ID=$(printf '%q' "freebsd:$release:$arch")
BUNDLE_DISTRO_RELEASE=$(printf '%q' "$release")
BUNDLE_KERNEL_RELEASE=$(printf '%q' "$arch")
BUNDLE_OS_RELEASE=$(printf '%q' "$release")
BUNDLE_ARCH=$(printf '%q' "$arch")
BUNDLE_DIR=$(printf '%q' "$bundle")
BUNDLE_DISK_IMAGE=$(printf '%q' "$bundle/freebsd-base.qcow2")
BUNDLE_SEED_ISO=$(printf '%q' "$bundle/cidata.iso")
BUNDLE_SOURCE_ISO=$(printf '%q' "$bundle/source.iso")
BUNDLE_SOURCE_ARCHIVE=$(printf '%q' "$bundle/packages/src.txz")
BUNDLE_PACKAGES=$(printf '%q' "$bundle/packages")
BUNDLE_BOOT_TYPE=disk
BUNDLE_CAPABILITIES=$(printf '%q' "$caps")
BUNDLE_FETCHED_AT=$(printf '%q' "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
EOF_FBSD_ENV
  (cd "$bundle/packages" && sha256sum "$vmfile" src.txz CHECKSUM.SHA256 MANIFEST > "$bundle/SHA256SUMS")
  rm -rf "$tmp"
  say "Normalized FreeBSD target: freebsd:$release:$arch"
}

provider_list_freebsd() {
  local release="$1"
  printf 'freebsd:%s:x86_64\n' "$release"
  printf 'freebsd:%s:aarch64\n' "$release"
}

session_rpc_get() {
  local socket="$1" remote="$2" local_file="$3"
  python3 - "$socket" "$remote" "$local_file" <<'PYRPCGET'
import base64, os, socket, sys, time, uuid
sockpath, remote, local = sys.argv[1:]
tok=uuid.uuid4().hex[:16]
s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM); end=time.time()+10
while True:
    try: s.connect(sockpath); break
    except OSError:
        if time.time()>=end: raise
        time.sleep(.1)
f=s.makefile('rwb',buffering=0)
p64=base64.b64encode(remote.encode()).decode(); f.write(f"GET {tok} {p64}\n".encode())
out=bytearray(); expected=None
while True:
    line=f.readline()
    if not line: raise SystemExit('control channel closed during download')
    p=line.decode('ascii','replace').rstrip('\r\n').split(' ',2)
    if len(p)<2 or p[1]!=tok: continue
    if p[0]=='GETERR': raise SystemExit(p[2] if len(p)>2 else 'guest download failed')
    if p[0]=='GETBEGIN': expected=int(p[2]) if len(p)>2 else None
    elif p[0]=='GETDATA' and len(p)>2: out.extend(base64.b64decode(p[2]))
    elif p[0]=='GETEND': break
if expected is not None and len(out)!=expected: raise SystemExit(f'download size mismatch: {len(out)} != {expected}')
os.makedirs(os.path.dirname(os.path.abspath(local)),exist_ok=True)
open(local,'wb').write(out)
print(len(out))
s.close()
PYRPCGET
}

freebsd_mount_source_command() {
  cat <<'EOF_FBSD_MOUNT'
if [ ! -d /usr/src/sys ]; then
  mkdir -p /mnt/klabsrc
  found=0
  for d in /dev/cd* /dev/vtbd*; do
    { [ -c "$d" ] || [ -b "$d" ]; } || continue
    umount /mnt/klabsrc >/dev/null 2>&1 || true
    if mount -t cd9660 "$d" /mnt/klabsrc >/dev/null 2>&1; then
      if [ -f /mnt/klabsrc/src.txz ]; then
        echo KLAB_EXTRACT_SOURCE "$d"
        tar -xJf /mnt/klabsrc/src.txz -C /
        found=1
        umount /mnt/klabsrc >/dev/null 2>&1 || true
        break
      fi
      umount /mnt/klabsrc >/dev/null 2>&1 || true
    fi
  done
  [ "$found" -eq 1 ] || { echo 'matching FreeBSD source ISO not found' >&2; exit 42; }
fi
EOF_FBSD_MOUNT
}


start_serial_relay() {
  local upstream="$1" proxy="$2" log="$3" pidfile="${2}.pid" launcher pid i
  rm -f "$proxy" "$pidfile"
  nohup python3 - "$upstream" "$proxy" "$pidfile" >"$log" 2>&1 <<'PYRELAY' &
import os, select, socket, sys, time
upstream_path, proxy_path, pidfile = sys.argv[1:]
if os.fork() != 0:
    os._exit(0)
os.setsid()
with open(pidfile, "w") as f:
    f.write(str(os.getpid()) + "\n")
def connect_upstream(timeout=None):
    deadline = time.monotonic() + timeout if timeout is not None else None
    while True:
        candidate = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            candidate.connect(upstream_path)
            candidate.setblocking(False)
            return candidate
        except OSError:
            candidate.close()
            if deadline is not None and time.monotonic() >= deadline:
                raise
            time.sleep(0.05)
up = connect_upstream(15)
try:
    os.unlink(proxy_path)
except FileNotFoundError:
    pass
listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
listener.bind(proxy_path)
listener.listen(4)
pending = bytearray()
client = None
while True:
    reads = [up, listener]
    if client is not None:
        reads.append(client)
    ready, _, _ = select.select(reads, [], [], 0.1)
    if client is not None and client in ready:
        try:
            data = client.recv(65536)
        except (ConnectionResetError, OSError):
            data = b''
        if data:
            try:
                up.sendall(data)
            except (BrokenPipeError, ConnectionResetError, OSError):
                up.close()
                up = connect_upstream()
                up.sendall(data)
        else:
            client.close()
            client = None
    if listener in ready:
        new_client, _ = listener.accept()
        if client is not None:
            client.close()
        client = new_client
        if pending:
            try:
                client.sendall(pending)
                pending.clear()
            except (BrokenPipeError, ConnectionResetError):
                client.close()
                client = None
    if up in ready:
        try:
            data = up.recv(65536)
        except (ConnectionResetError, OSError):
            data = b''
        if not data:
            up.close()
            up = connect_upstream()
            continue
        if client is None:
            pending.extend(data)
        else:
            try:
                client.sendall(data)
            except (BrokenPipeError, ConnectionResetError):
                client.close()
                client = None
                pending.extend(data)
PYRELAY
  launcher=$!
  for i in {1..150}; do
    if [[ -S "$proxy" && -s "$pidfile" ]]; then
      pid="$(cat "$pidfile")"
      if kill -0 "$pid" 2>/dev/null; then printf '%s\n' "$pid"; return 0; fi
    fi
    sleep 0.1
  done
  kill "$launcher" 2>/dev/null || true
  [[ -s "$pidfile" ]] && kill "$(cat "$pidfile")" 2>/dev/null || true
  return 1

}

boot_freebsd_session() {
  local target="$1" profile="$2" name="$3" crashdump="$4" panic_on_warn="$5"
  [[ "$profile" == normal ]] || die "FreeBSD release targets do not use Linux debug profiles"
  [[ "$panic_on_warn" == 1 ]] && say "FreeBSD backend: --panic-on-warn is not mapped to a FreeBSD tunable yet; panic/crash capture remains active"
  bundle_load "$target"
  [[ "${BUNDLE_BACKEND:-freebsd}" == freebsd ]] || die "target is not a FreeBSD backend"
  local bundle_arch="$(canonical_arch "${BUNDLE_ARCH:-$ARCH}")"
  [[ "$bundle_arch" == "$ARCH" ]] || die "FreeBSD target architecture is $bundle_arch but active architecture is $ARCH"
  have qemu-img || die "FreeBSD disk-backed sessions require qemu-img"
  local hash dir sock proxy qmp console pidfile pid relay_pid i overlay qemu firmware=""
  hash="$(printf '%s\n' "$LAB_HOME|$target|$ARCH|$profile" | sha256sum | cut -c1-12)"
  [[ -n "$name" ]] || name="f$hash"
  session_name_validate "$name"
  dir="$(session_dir "$name")"
  if [[ -f "$dir/pid" ]] && kill -0 "$(cat "$dir/pid")" 2>/dev/null; then die "session '$name' is already running"; fi
  rm -rf "$dir"; mkdir -p "$dir" "$SESSIONS" "$CRASHES"
  sock="/tmp/klab-${UID:-$(id -u)}-$hash.sock"; qmp="/tmp/klab-qmp-${UID:-$(id -u)}-$hash.sock"
  proxy="${sock%.sock}-proxy.sock"
  # A failed/panicked prior boot can leave its detached relay reconnecting to
  # this deterministic socket. Retire only that recorded relay before reuse.
  if [[ -s "${proxy}.pid" ]]; then
    relay_pid="$(cat "${proxy}.pid" 2>/dev/null || true)"
    [[ "$relay_pid" =~ ^[0-9]+$ ]] && kill "$relay_pid" 2>/dev/null || true
  fi
  rm -f "$sock" "$qmp" "$proxy" "${proxy}.pid"; console="$dir/console.log"; pidfile="$dir/pid"; overlay="$dir/root.qcow2"
  qemu-img create -q -f qcow2 -F qcow2 -b "$BUNDLE_DISK_IMAGE" "$overlay"
  qemu="$(require_qemu_arch "$ARCH")"
  # FreeBSD 15/aarch64 needs architectural behavior newer than the host's
  # Ubuntu 22.04 QEMU 6.2 provides. Prefer KLab's pinned QEMU 10 wrapper when
  # its offline image is installed; an explicit KLAB_QEMU still wins.
  if [[ "$ARCH" == aarch64 && -z "$QEMU_OVERRIDE" && -x "$SELF_DIR/tools/qemu10-aarch64-container" ]] &&
     have docker && docker image inspect "${KLAB_QEMU10_AARCH64_IMAGE:-klab-qemu10-aarch64:local}" >/dev/null 2>&1; then
    qemu="$SELF_DIR/tools/qemu10-aarch64-container"
  fi
  local accel=(); mapfile -t accel < <(qemu_accel_args "$ARCH")
  # Allow a bounded host-compatibility override without changing the proven
  # architecture default. This is useful when retesting old TCG versions.
  if [[ "$ARCH" == aarch64 && -n "${KLAB_FREEBSD_AARCH64_CPU:-}" ]] && ! qemu_kvm_compatible "$ARCH"; then
    accel=(-cpu "$KLAB_FREEBSD_AARCH64_CPU")
  fi
  local -a fwargs=()
  if [[ "$ARCH" == aarch64 ]]; then
    firmware="$(find_aarch64_uefi 2>/dev/null || true)"
    [[ -n "$firmware" ]] || die "FreeBSD/aarch64 requires UEFI firmware. Install qemu-efi-aarch64/AAVMF or set KLAB_AARCH64_UEFI=/path/to/QEMU_EFI.fd"
    fwargs=(-bios "$firmware")
  fi
  local machine; machine="$(qemu_machine_for_arch "$ARCH")"
  if [[ "$ARCH" == aarch64 && -n "${KLAB_FREEBSD_AARCH64_MACHINE:-}" ]] && ! qemu_kvm_compatible "$ARCH"; then
    machine="$KLAB_FREEBSD_AARCH64_MACHINE"
  fi
  local -a agent_serial=(-serial "unix:$sock,server=on,wait=off")
  if [[ "$ARCH" == aarch64 ]]; then
    agent_serial=(-chardev "socket,id=klabagent,path=$sock,server=on,wait=off" -device virtio-serial-pci,id=klabvserial -device virtserialport,chardev=klabagent,name=org.klab.agent)
  fi
  if [[ "$ssh_auth" == key ]]; then ssh_pub="$dir/authorized_key.pub"; ssh-keygen -y -f "$ssh_key" > "$ssh_pub" 2>"$dir/ssh-keygen-error.log" || die "could not derive a public key from $ssh_key"; fi
  local session_seed="$dir/cidata.iso"
  make_freebsd_seed_iso "$dir" "$ARCH" "$ssh_pub"
  local -a network=(-netdev user,id=klabnet,restrict=on -device virtio-net-pci,netdev=klabnet,mac=$ssh_mac)
  if [[ "$ssh_auth" != off ]]; then network=(-netdev "user,id=klabnet,restrict=on,hostfwd=tcp:${ssh_bind}:${ssh_port}-10.0.2.15:22" -device virtio-net-pci,netdev=klabnet,mac=$ssh_mac); fi
  say "Booting persistent FreeBSD session '$name' for $target [$ARCH] with guest networking"
  "$qemu" "${accel[@]}" -machine "$machine" "${fwargs[@]}" -m "$MEMORY" -smp "$CPUS" \
    -drive "file=$overlay,if=virtio,format=qcow2" \
    -drive "file=$session_seed,media=cdrom,format=raw,readonly=on" \
    -drive "file=$BUNDLE_SOURCE_ISO,media=cdrom,format=raw,readonly=on" \
    -display none "${network[@]}" -serial "file:$console" "${agent_serial[@]}" \
    -qmp "unix:$qmp,server=on,wait=off" -monitor none -no-reboot -daemonize -pidfile "$pidfile" \
    2>"$dir/qemu-error.log" || die "QEMU failed to start FreeBSD; see $dir/qemu-error.log"
  [[ -f "$pidfile" ]] || die "QEMU did not create a pid file"; pid="$(cat "$pidfile")"
  relay_pid="$(start_serial_relay "$sock" "$proxy" "$dir/control-relay.log")" || die "FreeBSD serial relay failed to start; see $dir/control-relay.log"
  printf 'SESSION_TARGET=%q\nSESSION_BACKEND=freebsd\nSESSION_ARCH=%q\nSESSION_PROFILE=normal\nSESSION_KERNEL=%q\nSESSION_DISK=%q\nSESSION_CONTROL=%q\nSESSION_CONTROL_UPSTREAM=%q\nSESSION_CONTROL_RELAY_PID=%q\nSESSION_QMP=%q\nSESSION_INITRD=%q\nSESSION_CRASHDUMP=%q\nSESSION_PANIC_ON_WARN=%q\nSESSION_SSH_ENABLED=%q\nSESSION_SSH_AUTH=%q\nSESSION_SSH_HOST=%q\nSESSION_SSH_BIND=%q\nSESSION_SSH_PORT=%q\nSESSION_SSH_KEY=%q\n' \
    "$target" "$ARCH" "$BUNDLE_DISK_IMAGE" "$overlay" "$proxy" "$sock" "$relay_pid" "$qmp" "" "$crashdump" "$panic_on_warn" "$([[ "$ssh_auth" != off ]] && echo 1 || echo 0)" "$ssh_auth" 127.0.0.1 "$ssh_bind" "$ssh_port" "$ssh_key" > "$dir/session.env"
  local freebsd_boot_timeout="$BOOT_TIMEOUT"; (( freebsd_boot_timeout < 180 )) && freebsd_boot_timeout=180
  if ! session_rpc_boot_ready "$proxy" "$freebsd_boot_timeout" >/dev/null 2>&1; then
    if crash_log_has_panic "$console"; then capture_session_crash "$name" || true; die "FreeBSD session '$name' panicked during boot; see $console"; fi
    if ! kill -0 "$pid" 2>/dev/null; then die "FreeBSD session '$name' exited during boot; see $console and $dir/qemu-error.log"; fi
    die "FreeBSD session '$name' control channel did not become ready within ${freebsd_boot_timeout}s; see $console"
  fi
  session_rpc_exec "$proxy" 'ifconfig vtnet0 up; dhclient vtnet0 >/tmp/klab-dhclient.log 2>&1 || true; i=0; while ! ifconfig vtnet0 2>/dev/null | grep -q "inet 10.0.2." && [ $i -lt 30 ]; do i=$((i+1)); sleep 1; done; ifconfig vtnet0; ifconfig vtnet0 | grep -q "inet 10.0.2."' 45 > "$dir/network.txt" 2>&1 || die "FreeBSD session '$name' failed guest networking; see $dir/network.txt"
  if [[ "$ssh_auth" == key ]]; then
    : > "$dir/openssh-start.txt"; local ssh_ready=0 attempt
    for attempt in {1..30}; do
      if timeout 15 ssh -i "$ssh_key" -p "$ssh_port" -o ConnectTimeout=5 -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@127.0.0.1" 'printf KLAB_FREEBSD_SSH_READY' >> "$dir/openssh-start.txt" 2>&1; then ssh_ready=1; break; fi
      sleep 1
    done
    [[ "$ssh_ready" == 1 ]] || die "FreeBSD session '$name' failed host SSH login; see $dir/openssh-start.txt"
  fi
  nohup bash "$SELF_PATH" _crash-watch "$name" >"$dir/crash-watcher.log" 2>&1 & printf '%s\n' "$!" > "$dir/crash-watcher.pid"
  say "FreeBSD session '$name' is ready"
  printf '%s\n' "$name"
}

build_freebsd_module() {
  local target="$1" module_dir="$2" job session tarball source_script rc=0 list remote base i source_rc
  require_target_capability "$target" module-build
  job="$(copy_module_job "$target" "$module_dir")"; MODULE_JOB="$job"
  session="fbld-$(printf '%s-%s' "$target" "$$" | sha256sum | cut -c1-10)"
  tarball="$job/module-src.tar.gz"; tar -C "$job/module" -czf "$tarball" .
  source_script="$job/freebsd-source-extract.sh"
  {
    printf '%s\n' '#!/bin/sh' '('
    freebsd_mount_source_command
    printf '%s\n' ')' 'rc=$?' 'printf "%s\n" "$rc" > /tmp/klab-source.rc' 'exit "$rc"'
  } > "$source_script"
  chmod +x "$source_script"
  cmd_boot_session "$target" --name "$session" >/dev/null
  load_session_env "$session"
  session_rpc_put_exec "$SESSION_CONTROL" "$tarball" /tmp/klab-module.tar.gz 0644 >/dev/null || rc=$?
  if (( rc == 0 )); then
    session_rpc_put_exec "$SESSION_CONTROL" "$source_script" /tmp/klab-source-extract.sh 0755 >/dev/null || rc=$?
  fi
  if (( rc == 0 )); then
    say "Starting FreeBSD source extraction"
    session_rpc_exec "$SESSION_CONTROL" 'rm -f /tmp/klab-source.rc /tmp/klab-source.log; /usr/sbin/daemon -f -o /tmp/klab-source.log /bin/sh /tmp/klab-source-extract.sh' || rc=$?
  fi
  if (( rc == 0 )); then
    for i in {1..360}; do
      if session_rpc_exec "$SESSION_CONTROL" 'test -f /tmp/klab-source.rc' >/dev/null 2>&1; then break; fi
      sleep 5
    done
    source_rc="$(session_rpc_exec "$SESSION_CONTROL" 'cat /tmp/klab-source.rc 2>/dev/null || echo 124')" || source_rc=124
    if [[ "$source_rc" != 0 ]]; then
      session_rpc_exec "$SESSION_CONTROL" 'cat /tmp/klab-source.log' >&2 || true
      rc="$source_rc"
    else
      say "FreeBSD source extraction complete; building module"
    fi
  fi
  if (( rc == 0 )); then
    session_rpc_exec "$SESSION_CONTROL" 'rm -rf /tmp/klab-module; mkdir -p /tmp/klab-module; tar -xzf /tmp/klab-module.tar.gz -C /tmp/klab-module; cd /tmp/klab-module; make SYSDIR=/usr/src/sys' 300 || rc=$?
  fi
  if (( rc == 0 )); then
    list="$(session_rpc_exec "$SESSION_CONTROL" "find /tmp/klab-module -type f -name '*.ko' -print | sort")" || rc=$?
    [[ -n "$list" ]] || rc=43
  fi
  if (( rc == 0 )); then
    while IFS= read -r remote; do
      [[ -n "$remote" ]] || continue
      base="$(basename "$remote")"
      session_rpc_get "$SESSION_CONTROL" "$remote" "$job/module/$base" >/dev/null || { rc=$?; break; }
    done <<<"$list"
  fi
  cmd_stop_session "$session" >/dev/null 2>&1 || true
  (( rc == 0 )) || die "FreeBSD module build failed for $target (rc=$rc)"
  mapfile -t MODULE_FILES < <(find "$job/module" -maxdepth 1 -type f -name '*.ko' -print | sort)
  ((${#MODULE_FILES[@]} > 0)) || die "FreeBSD build produced no .ko files"
}

run_freebsd_target_test() {
  local target="$1" module_dir="$2" test_script="$3" crashdump="${4:-0}" panic_on_warn="${5:-0}"
  local session rc=0 m remote
  [[ -f "$test_script" ]] || die "test script not found: $test_script"
  build_freebsd_module "$target" "$module_dir"
  session="ftst-$(printf '%s-%s' "$target" "$$" | sha256sum | cut -c1-10)"
  local -a boot_args=("$target" --name "$session")
  [[ "$crashdump" == 1 ]] && boot_args+=(--crashdump)
  [[ "$panic_on_warn" == 1 ]] && boot_args+=(--panic-on-warn)
  if ! cmd_boot_session "${boot_args[@]}" >/dev/null; then
    say "FreeBSD test boot failed: $target"
    return 1
  fi
  load_session_env "$session"
  for m in "${MODULE_FILES[@]}"; do
    remote="/tmp/klab-modules/$(basename "$m")"
    session_rpc_put_exec "$SESSION_CONTROL" "$m" "$remote" 0644 >/dev/null || { rc=$?; break; }
    session_rpc_exec "$SESSION_CONTROL" "kldload $(posix_shell_join "$remote")" || { rc=$?; break; }
  done
  if (( rc == 0 )); then
    session_rpc_put_exec "$SESSION_CONTROL" "$test_script" /tmp/klab-test.sh 0755 >/dev/null || rc=$?
  fi
  if (( rc == 0 )); then
    session_rpc_exec "$SESSION_CONTROL" '/bin/sh /tmp/klab-test.sh' || rc=$?
  fi
  session_rpc_exec "$SESSION_CONTROL" 'echo KLAB_DMESG_BEGIN; dmesg; echo KLAB_DMESG_END' || true
  cmd_stop_session "$session" >/dev/null 2>&1 || true
  if (( rc == 0 )); then say "FreeBSD test PASS: $target"; else say "FreeBSD test FAIL: $target rc=$rc"; fi
  return "$rc"
}

ensure_freebsd_examples() {
  mkdir -p "$EXAMPLES/freebsd-hello"
  if [[ ! -f "$EXAMPLES/freebsd-hello/hello.c" ]]; then
    cat > "$EXAMPLES/freebsd-hello/hello.c" <<'EOF_FBSD_C'
#include <sys/param.h>
#include <sys/kernel.h>
#include <sys/module.h>
#include <sys/systm.h>
static int klab_event(struct module *m, int event, void *arg) {
    switch (event) {
    case MOD_LOAD: uprintf("kernel_lab_hello: loaded\\n"); break;
    case MOD_UNLOAD: uprintf("kernel_lab_hello: unloaded\\n"); break;
    default: return EOPNOTSUPP;
    }
    return 0;
}
static moduledata_t klab_mod = { "kernel_lab_hello", klab_event, NULL };
DECLARE_MODULE(kernel_lab_hello, klab_mod, SI_SUB_DRIVERS, SI_ORDER_MIDDLE);
MODULE_VERSION(kernel_lab_hello, 1);
EOF_FBSD_C
    cat > "$EXAMPLES/freebsd-hello/Makefile" <<'EOF_FBSD_MK'
KMOD=kernel_lab_hello
SRCS=hello.c
.include <bsd.kmod.mk>
EOF_FBSD_MK
    cat > "$EXAMPLES/freebsd-test.sh" <<'EOF_FBSD_TEST'
#!/bin/sh
set -eu
kldstat | grep -q kernel_lab_hello
echo KLAB_FREEBSD_SMOKE_OK
EOF_FBSD_TEST
    chmod +x "$EXAMPLES/freebsd-test.sh"
  fi
}

cmd_load_module_session() {
  (($# >= 2)) || die "usage: $0 load-module <SESSION> <MODULE.ko> [module-args...]"
  local name="$1" module="$2"; shift 2
  [[ -f "$module" ]] || die "module not found: $module"
  load_session_env "$name"
  local backend="${SESSION_BACKEND:-linux}" remote="/tmp/klab-modules/$(basename "$module")" args command
  session_rpc_put "$SESSION_CONTROL" "$module" "$remote" 0644 >/dev/null
  case "$backend" in
    linux)
      args="$(posix_shell_join "$@")"; command="insmod $(posix_shell_join "$remote")"; [[ -n "$args" ]] && command+=" $args"
      ;;
    freebsd)
      (($# == 0)) || die "FreeBSD kldload backend does not accept Linux-style module parameters; configure tunables/sysctls separately"
      command="kldload $(posix_shell_join "$remote")"
      ;;
    *) die "session backend '$backend' does not implement module-load" ;;
  esac
  session_rpc_exec "$SESSION_CONTROL" "$command"
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(sha256sum "$module" | awk '{print $1}')" "$(readlink -f "$module")" >> "$(session_dir "$name")/loaded-modules.tsv"
}

cmd_unload_module_session() {
  (($# == 2)) || die "usage: $0 unload-module <SESSION> <MODULE-NAME>"
  local name="$1" mod="$2"; load_session_env "$name"
  case "${SESSION_BACKEND:-linux}" in
    linux) session_rpc_exec "$SESSION_CONTROL" "rmmod $(posix_shell_join "$mod")" ;;
    freebsd) session_rpc_exec "$SESSION_CONTROL" "kldunload $(posix_shell_join "$mod")" ;;
    *) die "session backend '${SESSION_BACKEND:-unknown}' does not implement module-unload" ;;
  esac
}

cmd_list_modules_session() {
  (($# == 1)) || die "usage: $0 list-modules <SESSION>"
  local name="$1"; load_session_env "$name"
  case "${SESSION_BACKEND:-linux}" in
    linux) session_rpc_exec "$SESSION_CONTROL" 'lsmod' ;;
    freebsd) session_rpc_exec "$SESSION_CONTROL" 'kldstat' ;;
    *) die "session backend '${SESSION_BACKEND:-unknown}' does not implement module-list" ;;
  esac
}


# KLAB_PROVIDER_REFACTOR_M2
# Unified provider dispatcher. Provider policy lives in providers/*.sh and
# package-manager mechanics live in lib/backends/*.sh.
# shellcheck disable=SC1091
source "$SELF_DIR/lib/provider-core.sh"

providers_show() { klab_provider_show; }

provider_list_apt() {
  local provider="$1" release="$2" pattern="${3:-}" image prep regex
  image="$(provider_image "$provider" "$release")"
  prep="$(apt_snapshot_setup_script "$provider" "$release")"
  case "$provider" in
    ubuntu) regex='^linux-image-[0-9].*-(generic|lowlatency|aws|azure|gcp|oracle|oem|realtime|gke)$' ;;
    debian) regex='^linux-image-[0-9].*-(amd64|cloud-amd64|rt-amd64)$' ;;
  esac
  say "Listing $provider kernels from $release"
  run_container_root "$image" bash -lc "$prep
apt-cache dumpavail | awk -v RS= -F '\\n' '{ for (i=1; i<=NF; i++) if (\$i ~ /^Package: /) { print substr(\$i,10); break } }' | grep -E '$regex' | sed 's/^linux-image-//' | sort -Vu | ${pattern:+grep -F '$pattern' | }tail -n 2000"
}

provider_list_fedora() {
  local release="$1" pattern="${2:-}" image ptn hub topurl qhub qtop
  release_snapshot_parts "$release"
  image="${KLAB_FEDORA_KOJI_IMAGE:-fedora:43}"
  hub="${KLAB_FEDORA_KOJI_HUB:-https://koji.fedoraproject.org/kojihub}"
  topurl="${KLAB_FEDORA_KOJI_TOPURL:-https://kojipkgs.fedoraproject.org/}"
  if [[ "${KLAB_MIRROR_ONLY:-0}" == 1 ]]; then
    [[ -n "${KLAB_FEDORA_KOJI_HUB:-}" && -n "${KLAB_FEDORA_KOJI_TOPURL:-}" ]] || die "mirror-only: Fedora Koji requires explicit KLAB_FEDORA_KOJI_HUB and KLAB_FEDORA_KOJI_TOPURL"
  fi
  ptn="${pattern:-*}"; printf -v qhub '%q' "$hub"; printf -v qtop '%q' "$topurl"
  say "Listing completed Fedora $RELEASE_BASE kernel builds from Koji"
  run_container_root "$image" bash -lc "set -o pipefail
    dnf -qy install koji >/dev/null 2>&1
    raw=\$(koji --server=$qhub --topurl=$qtop list-builds --package=kernel --state=COMPLETE --pattern='kernel-${ptn}*fc${RELEASE_BASE}*')
    printf '%s\n' "\$raw" | awk '\$1 ~ /^kernel-[0-9]/ {print \$1}' | sed 's/^kernel-//' | grep -E '^[A-Za-z0-9._+~-]+\.fc${RELEASE_BASE}$' | sed 's/\$/.${ARCH}/' | tail -n 200"
}

provider_list_centos() {
  local release="$1" pattern="${2:-}" image
  image="$(provider_image centos "$release")"
  say "Listing CentOS $release kernel-core builds"
  run_container_root "$image" bash -lc "dnf -qy install dnf-plugins-core >/dev/null; dnf -q repoquery --available --show-duplicates --qf '%{evr}.%{arch}' kernel-core | sort -V | ${pattern:+grep -F '$pattern' | }tail -n 200"
}

provider_list_rhel() {
  local release="$1" pattern="${2:-}"
  if image="$(provider_image rhel "$release" 2>/dev/null)"; then
    run_container_root "$image" bash -lc "dnf -qy install dnf-plugins-core >/dev/null || true; dnf -q repoquery --available --show-duplicates --qf '%{evr}.%{arch}' kernel-core | sort -V | ${pattern:+grep -F '$pattern' | }tail -n 200"
  else
    have dnf || die "RHEL listing requires an entitled host with dnf, or set KLAB_RHEL_IMAGE"
    dnf -q repoquery --available --show-duplicates --qf '%{evr}.%{arch}' kernel-core | sort -V | { if [[ -n "$pattern" ]]; then grep -F "$pattern"; else cat; fi; } | tail -n 200
  fi
}

cmd_provider_list() {
  [[ "$OFFLINE" != 1 ]] || die "offline mode: provider listing requires network access"
  local spec="$1" pattern="${2:-}"
  [[ -z "$pattern" ]] || validate_token "$pattern" pattern
  parse_target "$spec"
  [[ -z "$KERNEL_RELEASE" ]] || die "list expects provider:release, not a kernel release"
  case "$PROVIDER" in
    upstream)
      git -C "$SRC" tag -l "v${pattern:-*}" | tail -n 200
      ;;
    freebsd)
      provider_list_freebsd "$DISTRO_RELEASE"
      ;;
    *)
      klab_provider_list "$PROVIDER" "$DISTRO_RELEASE" "$pattern"
      ;;
  esac
}

extract_debs() {
  local packages="$1" root="$2" image="$3"
  rm -rf "$root"; mkdir -p "$root"
  if have dpkg-deb; then
    local p
    shopt -s nullglob
    for p in "$packages"/*.deb; do dpkg-deb -x "$p" "$root"; done
    shopt -u nullglob
  else
    run_container_user "$image" -v "$packages:/pkgs:ro" -v "$root:/rootfs" bash -lc 'for p in /pkgs/*.deb; do dpkg-deb -x "$p" /rootfs; done'
  fi
}

extract_rpms() {
  local packages="$1" root="$2"
  rm -rf "$root"; mkdir -p "$root"
  if have rpm2cpio && have cpio; then
    local p
    shopt -s nullglob
    for p in "$packages"/*.rpm; do (cd "$root" && rpm2cpio "$p" | cpio -idm --quiet --no-absolute-filenames); done
    shopt -u nullglob
  else
    local owner; owner="$(klab_provider_bind_output_owner)"
    run_container_root fedora:43 -v "$packages:/pkgs:ro" -v "$root:/rootfs" bash -lc "dnf -qy install cpio >/dev/null; for p in /pkgs/*.rpm; do (cd /rootfs && rpm2cpio "\$p" | cpio -idm --quiet --no-absolute-filenames); done; chown -R $owner /rootfs"
  fi
  chmod -R u+rX "$root"
}

write_package_manifest() {
  local bundle="$1"
  if have sha256sum; then
    (cd "$bundle/packages" && for f in *.deb *.rpm *.apk; do [[ -f "$f" ]] || continue; sha256sum -- "$f"; done | LC_ALL=C sort -k2) > "$bundle/packages/PACKAGES.sha256"
    cp "$bundle/packages/PACKAGES.sha256" "$bundle/SHA256SUMS"
  fi
}

normalize_bundle() {
  local provider="$1" release="$2" krel="$3" bundle="$4" build_image="$5"
  local root="$bundle/root" image modules build candidate

  image=""
  for candidate in \
      "$root/boot/vmlinuz-$krel" \
      "$root/usr/lib/modules/$krel/vmlinuz" \
      "$root/lib/modules/$krel/vmlinuz"; do
    [[ -f "$candidate" ]] && { image="$candidate"; break; }
  done
  if [[ -z "$image" ]]; then
    image="$(find "$root/boot" "$root/usr/lib/modules" "$root/lib/modules" -type f -name 'vmlinuz*' 2>/dev/null | grep -F "$krel" | head -n1 || true)"
  fi
  [[ -n "$image" && -f "$image" ]] || die "could not locate vmlinuz for $krel after extracting packages"
  cp -f "$image" "$bundle/vmlinuz"

  modules=""
  for candidate in "$root/lib/modules/$krel" "$root/usr/lib/modules/$krel"; do
    [[ -d "$candidate" ]] && { modules="$candidate"; break; }
  done

  build=""
  for candidate in \
      "$root/usr/src/linux-headers-$krel" \
      "$root/usr/src/kernels/$krel" \
      "$root/usr/lib/modules/$krel/build" \
      "$root/lib/modules/$krel/build"; do
    [[ -d "$candidate" ]] && { build="$candidate"; break; }
  done
  if [[ -z "$build" ]]; then
    build="$(find "$root/usr/src" -mindepth 1 -maxdepth 2 -type d \( -name "*${krel}*" -o -name "$krel" \) 2>/dev/null | head -n1 || true)"
  fi
  [[ -n "$build" && -d "$build" ]] || die "could not locate module build/header tree for $krel"

  local compiler_parsed="" compiler_family="" compiler_version="" compiler_banner=""
  compiler_parsed="$(detect_compiler_from_build_tree "$build" 2>/dev/null || true)"
  if [[ -n "$compiler_parsed" ]]; then
    IFS=$'\t' read -r compiler_family compiler_version compiler_banner <<<"$compiler_parsed"
  fi

  {
    printf 'BUNDLE_PROVIDER=%q\n' "$provider"
    printf 'BUNDLE_DISTRO_RELEASE=%q\n' "$release"
    printf 'BUNDLE_KERNEL_RELEASE=%q\n' "$krel"
    printf 'BUNDLE_ARCH=%q\n' "$ARCH"
    printf 'BUNDLE_DIR=%q\n' "$bundle"
    printf 'BUNDLE_PACKAGES=%q\n' "$bundle/packages"
    printf 'BUNDLE_ROOT=%q\n' "$root"
    printf 'BUNDLE_KERNEL_IMAGE=%q\n' "$bundle/vmlinuz"
    printf 'BUNDLE_BUILD_DIR=%q\n' "$build"
    printf 'BUNDLE_MODULES_DIR=%q\n' "$modules"
    printf 'BUNDLE_BUILD_IMAGE=%q\n' "$build_image"
    printf 'BUNDLE_FETCHED_AT=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'BUNDLE_KERNEL_COMPILER_FAMILY=%q\n' "$compiler_family"
    printf 'BUNDLE_KERNEL_COMPILER_VERSION=%q\n' "$compiler_version"
    printf 'BUNDLE_KERNEL_COMPILER_BANNER=%q\n' "$compiler_banner"
  } > "$bundle/bundle.env"

  cat > "$bundle/README.kernel-lab" <<EOF
provider=$provider
release=$release
kernel_release=$krel
kernel_image=$bundle/vmlinuz
build_tree=$build
modules_tree=${modules:-none}
original_packages=$bundle/packages
build_container=${build_image:-host}
EOF
  say "Normalized bundle: $bundle"
}

fetch_apt_bundle() {
  local provider="$1" release="$2" krel="$3" bundle="$4" image prep
  local packages="$bundle/packages" root="$bundle/root"
  image="$(provider_image "$provider" "$release")"
  prep="$(apt_snapshot_setup_script "$provider" "$release")"
  mkdir -p "$packages"
  rm -f "$packages"/*.deb 2>/dev/null || true

  say "Downloading $provider $release kernel $krel"
  run_container_root "$image" -v "$packages:/out" bash -lc "$prep
mkdir -p /out/partial
pkgs=''
for p in linux-image-$krel linux-modules-$krel linux-modules-extra-$krel linux-headers-$krel; do
  if apt-cache show \"\$p\" >/dev/null 2>&1; then pkgs=\"\$pkgs \$p\"; fi
done
[ -n \"\$pkgs\" ] || { echo 'no matching kernel packages found' >&2; exit 40; }
echo \"Downloading:\$pkgs\" >&2
DEBIAN_FRONTEND=noninteractive apt-get -y --download-only --no-install-recommends -o Dir::Cache::archives=/out install \$pkgs
rm -rf /out/lock /out/partial"
  compgen -G "$packages/*.deb" >/dev/null || die "no .deb files were downloaded"
  write_package_manifest "$bundle"
  extract_debs "$packages" "$root" "$image"
  normalize_bundle "$provider" "$release" "$krel" "$bundle" "$image"
}

fetch_fedora_bundle() {
  local release="$1" krel="$2" bundle="$3" image nvr hub topurl owner qhub qtop helper
  release_snapshot_parts "$release"
  image="${KLAB_FEDORA_KOJI_IMAGE:-fedora:43}"
  hub="${KLAB_FEDORA_KOJI_HUB:-https://koji.fedoraproject.org/kojihub}"
  topurl="${KLAB_FEDORA_KOJI_TOPURL:-https://kojipkgs.fedoraproject.org/}"
  if [[ "${KLAB_MIRROR_ONLY:-0}" == 1 ]]; then
    [[ -n "${KLAB_FEDORA_KOJI_HUB:-}" && -n "${KLAB_FEDORA_KOJI_TOPURL:-}" ]] || die "mirror-only: Fedora Koji requires explicit KLAB_FEDORA_KOJI_HUB and KLAB_FEDORA_KOJI_TOPURL"
  fi
  nvr="${krel%.x86_64}"; nvr="${nvr%.aarch64}"; nvr="kernel-$nvr"
  helper="$SELF_DIR/lib/fedora_koji.py"; [[ -f "$helper" ]] || die "Fedora Koji metadata helper is missing: $helper"
  owner="$(klab_provider_bind_output_owner)"; printf -v qhub '%q' "$hub"; printf -v qtop '%q' "$topurl"
  mkdir -p "$bundle/packages"; rm -f "$bundle/packages"/*.rpm 2>/dev/null || true
  say "Downloading Fedora Koji build $nvr and capturing its exact $ARCH buildroot provenance"
  run_container_root "$image" -v "$bundle:/bundle" -v "$helper:/klab/fedora_koji.py:ro" bash -lc "set -eu
    dnf -qy install koji python3-koji >/dev/null 2>&1
    cd /bundle/packages
    koji --server=$qhub --topurl=$qtop download-build --noprogress --arch=$ARCH '$nvr'
    python3 /klab/fedora_koji.py capture --hub $qhub --nvr '$nvr' --arch '$ARCH' --output /bundle/koji-buildroot.json >/bundle/koji-buildroot.capture
    chown -R '$owner' /bundle"
  compgen -G "$bundle/packages/*.rpm" >/dev/null || die "Koji returned no RPMs for $nvr"
  [[ -s "$bundle/koji-buildroot.json" ]] || die "Koji buildroot provenance was not captured for $nvr"
  write_package_manifest "$bundle"
  extract_rpms "$bundle/packages" "$bundle/root"
  normalize_bundle fedora "$release" "$krel" "$bundle" "$image"
  cat >>"$bundle/bundle.env" <<EOF_KOJI
BUNDLE_FEDORA_KOJI_BUILDROOT_JSON=$(printf '%q' "$bundle/koji-buildroot.json")
BUNDLE_FEDORA_KOJI_HUB=$(printf '%q' "$hub")
BUNDLE_FEDORA_KOJI_TOPURL=$(printf '%q' "$topurl")
EOF_KOJI
}

fetch_centos_bundle() {
  local release="$1" krel="$2" bundle="$3" image
  image="$(provider_image centos "$release")"
  mkdir -p "$bundle/packages"
  rm -f "$bundle/packages"/*.rpm 2>/dev/null || true
  say "Downloading CentOS $release kernel $krel"
  run_container_root "$image" -v "$bundle/packages:/out" bash -lc "dnf -qy install dnf-plugins-core >/dev/null
pkgs=''
for p in kernel-core-$krel kernel-modules-core-$krel kernel-modules-$krel kernel-modules-extra-$krel kernel-devel-$krel; do
  if dnf -q repoquery \"\$p\" | grep -q .; then pkgs=\"\$pkgs \$p\"; fi
done
[ -n \"\$pkgs\" ] || { echo 'no matching RPMs found' >&2; exit 40; }
dnf -qy download --resolve --alldeps --destdir /out \$pkgs"
  compgen -G "$bundle/packages/*.rpm" >/dev/null || die "no RPMs were downloaded"
  write_package_manifest "$bundle"
  extract_rpms "$bundle/packages" "$bundle/root"
  normalize_bundle centos "$release" "$krel" "$bundle" "$image"
}

fetch_rhel_bundle() {
  local release="$1" krel="$2" bundle="$3" image=""
  mkdir -p "$bundle/packages"
  rm -f "$bundle/packages"/*.rpm 2>/dev/null || true
  if image="$(provider_image rhel "$release" 2>/dev/null)"; then
    say "Downloading RHEL $release kernel $krel using $image"
    run_container_root "$image" -v "$bundle/packages:/out" bash -lc "dnf -qy install dnf-plugins-core >/dev/null || true
pkgs=''
for p in kernel-core-$krel kernel-modules-core-$krel kernel-modules-$krel kernel-modules-extra-$krel kernel-devel-$krel; do
  if dnf -q repoquery \"\$p\" | grep -q .; then pkgs=\"\$pkgs \$p\"; fi
done
[ -n \"\$pkgs\" ] || exit 40
dnf -qy download --resolve --alldeps --destdir /out \$pkgs"
  else
    have dnf || die "RHEL fetch requires an entitled host with dnf, or KLAB_RHEL_IMAGE"
    have rpm2cpio || say "rpm2cpio is not installed; extraction will use a Fedora container"
    have dnf || die "dnf is required"
    dnf -qy download --resolve --alldeps --destdir "$bundle/packages" \
      "kernel-core-$krel" "kernel-devel-$krel" || die "RHEL download failed; verify entitlement and exact kernel release"
    image="${KLAB_RHEL_IMAGE:-}"
  fi
  compgen -G "$bundle/packages/*.rpm" >/dev/null || die "no RHEL RPMs were downloaded"
  write_package_manifest "$bundle"
  extract_rpms "$bundle/packages" "$bundle/root"
  normalize_bundle rhel "$release" "$krel" "$bundle" "$image"
}

cmd_fetch() {
  [[ "$OFFLINE" != 1 ]] || die "offline mode: fetch is disabled; import a .klab bundle instead"
  local target="$1" bundle
  parse_target "$target"
  case "$PROVIDER" in
    upstream)
      [[ -z "$KERNEL_RELEASE" ]] || die "use upstream:v6.6 (two fields), not upstream:release:kernel"
      prepare_build "$DISTRO_RELEASE" normal "$ARCH" >/dev/null
      say "Upstream build cached for $DISTRO_RELEASE [$ARCH]"
      return
      ;;
    freebsd)
      [[ -n "$KERNEL_RELEASE" ]] || die "FreeBSD fetch needs an architecture (normally use: $0 prepare freebsd:$DISTRO_RELEASE --arch x86_64|aarch64; 32-bit FreeBSD remains capability-gated)"
      local farch; farch="$(canonical_arch "$KERNEL_RELEASE")"; set_active_arch "$farch"
      bundle="$(bundle_dir_for "$PROVIDER" "$DISTRO_RELEASE" "$farch" "$ARCH")"
      if [[ -f "$bundle/bundle.env" && "${KLAB_REFETCH:-0}" != 1 ]]; then say "Already cached: $bundle"; printf '%s\n' "$bundle"; return; fi
      mkdir -p "$bundle"; fetch_freebsd_bundle "$DISTRO_RELEASE" "$ARCH" "$bundle"; printf '%s\n' "$bundle"; return
      ;;
  esac
  [[ -n "$KERNEL_RELEASE" ]] || die "fetch requires provider:release:kernel-release"
  bundle="$(bundle_dir_for "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$ARCH")"
  if [[ -f "$bundle/bundle.env" && "${KLAB_REFETCH:-0}" != 1 ]]; then
    say "Already cached: $bundle (set KLAB_REFETCH=1 to refresh)"
    printf '%s\n' "$bundle"
    return
  fi
  mkdir -p "$bundle"
  klab_provider_fetch "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$bundle"
  printf '%s\n' "$bundle"
}

cmd_info() {
  bundle_load "$1"
  local backend="${BUNDLE_BACKEND:-$(backend_for_provider "$BUNDLE_PROVIDER")}" caps="${BUNDLE_CAPABILITIES:-$(backend_capabilities "${BUNDLE_BACKEND:-$(backend_for_provider "$BUNDLE_PROVIDER")}")}"
  if [[ "$backend" == freebsd ]]; then
    cat <<EOF
Provider:        $BUNDLE_PROVIDER
Backend:         freebsd
Target:          ${BUNDLE_TARGET_ID:-$1}
FreeBSD release: ${BUNDLE_OS_RELEASE:-$BUNDLE_DISTRO_RELEASE}
Architecture:    ${BUNDLE_ARCH:-$BUNDLE_KERNEL_RELEASE}
Boot disk:       ${BUNDLE_DISK_IMAGE:-?}
Source archive:  ${BUNDLE_SOURCE_ARCHIVE:-?}
Seed image:      ${BUNDLE_SEED_ISO:-?}
Capabilities:    $caps
Fetched:         ${BUNDLE_FETCHED_AT:-?}
EOF
    return
  fi
  cat <<EOF
Provider:        $BUNDLE_PROVIDER
Backend:         $backend
Distro release:  $BUNDLE_DISTRO_RELEASE
Kernel release:  $BUNDLE_KERNEL_RELEASE
Kernel image:    $BUNDLE_KERNEL_IMAGE
Build tree:      $BUNDLE_BUILD_DIR
Modules tree:    ${BUNDLE_MODULES_DIR:-none}
Original pkgs:   $BUNDLE_PACKAGES
Build container: ${BUNDLE_BUILD_IMAGE:-host}
Fetched:         $BUNDLE_FETCHED_AT
Capabilities:    $caps
Guest userspace: ${BUNDLE_GUEST_USERSPACE_SPEC:-busybox-static}
Guest artifact:  ${BUNDLE_GUEST_ROOTFS:-${BUNDLE_GUEST_BUSYBOX:-none}}
EOF
  if [[ -n "${BUNDLE_BUILDENV_ID:-}" ]]; then
    printf 'Buildenv ID:     %s\n' "$BUNDLE_BUILDENV_ID"
  fi
  if [[ -n "${BUNDLE_KERNEL_COMPILER_FAMILY:-}" ]]; then
    printf 'Kernel compiler: %s %s\n' "$BUNDLE_KERNEL_COMPILER_FAMILY" "${BUNDLE_KERNEL_COMPILER_VERSION:-?}"
  fi
  if [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 ]]; then
    cat <<EOF
Toolchain bound: yes
Toolchain ID:    ${BUNDLE_TOOLCHAIN_ID:-unknown}
Compiler:        ${BUNDLE_TOOLCHAIN_FAMILY:-?} ${BUNDLE_TOOLCHAIN_VERSION:-?}
Compiler target: ${BUNDLE_TOOLCHAIN_TARGET:-?}
Compiler path:   ${BUNDLE_TOOLCHAIN_CC:-?}
EOF
  else
    printf 'Toolchain bound: no\n'
  fi
}

copy_module_job() {
  local target="$1" module_dir="$2" safe job
  module_dir="$(readlink -f "$module_dir")"
  [[ -d "$module_dir" ]] || die "module directory does not exist: $module_dir"
  safe="$(printf '%s' "$target" | tr ':@/' '___')"
  job="$JOBS_ROOT/${safe}-$$-$(date +%s%N)"
  mkdir -p "$job/module"
  cp -a "$module_dir/." "$job/module/"
  printf '%s\n' "$job"
}

build_external_module_bundle() {
  local target="$1" module_dir="$2" job provider image
  bundle_load "$target"
  job="$(copy_module_job "$target" "$module_dir")"
  provider="$BUNDLE_PROVIDER"
  image="$BUNDLE_BUILD_IMAGE"
  say "Building module for $target in isolated job $(basename "$job")"

  # Exact distro build roots run in a captured read-only sandbox. Compiler
  # execution is either a relocatable sealed toolchain (gcc-v1) or the actual
  # distribution compiler/binutils preserved inside the root (distro-native-v1).
  if [[ -n "${BUNDLE_BUILDENV_ID:-}" ]]; then
    local __be_meta __be_contract __be_dtid
    __be_meta="$(KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" assert-installed "$BUNDLE_BUILDENV_ID" --provider "$BUNDLE_PROVIDER" --release "$BUNDLE_DISTRO_RELEASE" --kernel-release "$BUNDLE_KERNEL_RELEASE" --target-arch "${BUNDLE_ARCH:-$ARCH}" --json)"
    IFS=$'\t' read -r __be_contract __be_dtid < <(python3 - "$__be_meta" <<'PY_BE_MODE'
import json,sys
m=json.loads(sys.argv[1]); print((m.get('compiler_contract') or 'gcc-v1')+'\t'+(m.get('distro_toolchain_id') or ''))
PY_BE_MODE
    )
    if [[ "$__be_contract" == distro-native-v1 ]]; then
      [[ "$__be_dtid" =~ ^[0-9a-f]{64}$ ]] || die "distro-native buildenv has no valid distro-toolchain binding"
      [[ "${BUNDLE_DISTRO_TOOLCHAIN_ID:-}" == "$__be_dtid" ]] || die "target distro-toolchain reference does not match buildenv binding"
      KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$DISTRO_TOOLCHAIN_BIN" assert-installed "$__be_dtid" --provider "$BUNDLE_PROVIDER" --release "$BUNDLE_DISTRO_RELEASE" --arch "${BUNDLE_ARCH:-$ARCH}" >/dev/null
      KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" run-module-native "$BUNDLE_BUILDENV_ID" --module "$job/module" --jobs "$JOBS" --kernel-arch "$(linux_karch "${BUNDLE_ARCH:-$ARCH}")" --expect-provider "$BUNDLE_PROVIDER" --expect-release "$BUNDLE_DISTRO_RELEASE" --expect-kernel-release "$BUNDLE_KERNEL_RELEASE" --expect-target-arch "${BUNDLE_ARCH:-$ARCH}"
    elif [[ "$__be_contract" == gcc-v1 ]]; then
      [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 ]] || die "target references gcc-v1 .klabbuildenv but has no bound .klabtoolchain"
      local __be_tc_tree="${BUNDLE_TOOLCHAIN_TREE_SHA256:-}"
      if [[ -z "$__be_tc_tree" && -f "$BUNDLE_TOOLCHAIN_DIR/.klab-toolchain-boundary.json" ]]; then
        __be_tc_tree="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tree_sha256",""))' "$BUNDLE_TOOLCHAIN_DIR/.klab-toolchain-boundary.json")"
      fi
      if [[ -z "$__be_tc_tree" ]]; then __be_tc_tree="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("toolchain_tree_sha256", ""))' "$__be_meta")"; fi
      [[ -n "$__be_tc_tree" ]] || die "target references .klabbuildenv but its verified manifest does not pin a toolchain tree"
      local be_args=(run-module "$BUNDLE_BUILDENV_ID" --toolchain-root "$BUNDLE_TOOLCHAIN_DIR" --toolchain-cc "$BUNDLE_TOOLCHAIN_CC_REL" --toolchain-tree-sha256 "$__be_tc_tree" --toolchain-family "${BUNDLE_TOOLCHAIN_FAMILY:-gcc}" --toolchain-version "${BUNDLE_TOOLCHAIN_VERSION:-}" --toolchain-target "${BUNDLE_TOOLCHAIN_TARGET:-}" --module "$job/module" --jobs "$JOBS" --kernel-arch "$(linux_karch "${BUNDLE_ARCH:-$ARCH}")" --expect-provider "$BUNDLE_PROVIDER" --expect-release "$BUNDLE_DISTRO_RELEASE" --expect-kernel-release "$BUNDLE_KERNEL_RELEASE" --expect-target-arch "${BUNDLE_ARCH:-$ARCH}")
      [[ -n "${BUNDLE_TOOLCHAIN_CROSS_PREFIX_REL:-}" ]] && be_args+=(--cross-prefix "$BUNDLE_TOOLCHAIN_CROSS_PREFIX_REL")
      KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" "${be_args[@]}"
    else
      die "unsupported buildenv compiler contract: $__be_contract"
    fi
    mapfile -t MODULE_FILES < <(find "$job/module" -type f -name '*.ko' -print | sort)
    ((${#MODULE_FILES[@]} > 0)) || die "no .ko files were produced for $target in buildenv $BUNDLE_BUILDENV_ID"
    MODULE_JOB="$job"
    return
  fi

  if [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 || "$OFFLINE" == 1 ]]; then
    if [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 ]]; then
      say "Building against the distro build tree with its .klab-bound toolchain"
    else
      say "Offline mode: building against the imported/extracted distro build tree on the host"
    fi
    prepare_bound_toolchain
    local karch
    karch="$(linux_karch_for_source "${BUNDLE_ARCH:-$ARCH}" "${BUNDLE_SOURCE_DIR:-$BUNDLE_BUILD_DIR}")"
    bound_make -s -C "$BUNDLE_BUILD_DIR" ARCH="$karch" M="$job/module" clean || true
    bound_make -C "$BUNDLE_BUILD_DIR" ARCH="$karch" M="$job/module" -j"$JOBS" modules
    mapfile -t MODULE_FILES < <(find "$job/module" -type f -name '*.ko' -print | sort)
    ((${#MODULE_FILES[@]} > 0)) || die "no .ko files were produced for $target"
    MODULE_JOB="$job"
    return
  fi

  klab_provider_build_module "$provider" "$BUNDLE_DISTRO_RELEASE" \
    "$BUNDLE_KERNEL_RELEASE" "$image" "$BUNDLE_PACKAGES" "$job/module" "$JOBS" \
    "$BUNDLE_BUILD_DIR" "${BUNDLE_ARCH:-$ARCH}"

  mapfile -t MODULE_FILES < <(find "$job/module" -type f -name '*.ko' -print | sort)
  ((${#MODULE_FILES[@]} > 0)) || die "no .ko files were produced for $target"
  MODULE_JOB="$job"
}

make_initramfs_bundle() {
  local target="$1" key="$2" test_script="$3"; shift 3
  local image root
  bundle_load "$target"
  image="$(make_initramfs "$key" "$test_script" "$@")" || die "failed to create base initramfs for $key"
  if [[ "$INCLUDE_DISTRO_MODULES" == 1 && -n "${BUNDLE_MODULES_DIR:-}" && -d "$BUNDLE_MODULES_DIR" ]]; then
    root="$INITRAMFS/$key.root"
    say "Including distro module tree (experimental; may make initramfs large)"
    mkdir -p "$root/lib/modules"
    cp -a "$BUNDLE_MODULES_DIR" "$root/lib/modules/$BUNDLE_KERNEL_RELEASE"
    (cd "$root" && find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -1) > "$image"
  fi
  printf '%s\n' "$image"
}

cmd_distro_test() {
  local target="$1" module_dir="$2" test_script="$3" key initrd
  parse_target "$target"
  [[ -n "$KERNEL_RELEASE" ]] || die "distro test requires provider:release:kernel-release"
  if [[ ! -f "$(bundle_dir_for "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE")/bundle.env" ]]; then
    if [[ "$OFFLINE" == 1 ]]; then
      die "offline lab: target is not imported: $target\nTransfer its .klab file and run: $0 import FILE.klab"
    elif [[ "${KLAB_AUTO_FETCH:-0}" == 1 ]]; then
      cmd_fetch "$target" >/dev/null
    else
      die "target is not prepared locally: $target\nRun '$0 prepare $target' on the staging machine, or set KLAB_AUTO_FETCH=1 for legacy implicit fetching"
    fi
  fi
  bundle_load "$target"
  build_external_module_bundle "$target" "$module_dir"
  key="$(printf '%s' "$target" | tr ':@/' '___')"
  initrd="$(make_initramfs_bundle "$target" "$key" "$test_script" "${MODULE_FILES[@]}")" || die "failed to create distro initramfs for $target"
  run_qemu_image "$key" "$BUNDLE_KERNEL_IMAGE" "$initrd"
}



prepare_cached_upstream_toolchain() {
  local build="$1" envfile="$build/.klab-compiler.env" wanted_arch
  wanted_arch="$(canonical_arch "$(cat "$build/.klab-arch" 2>/dev/null || echo x86_64)")"
  KLAB_TC_PATH="$PATH"
  KLAB_TC_MAKE_ARGS=()
  KLAB_TC_LIBRARY_PATH=""
  [[ -f "$envfile" ]] || return 0

  unset KLAB_KERNEL_COMPILER_FAMILY KLAB_KERNEL_COMPILER_VERSION KLAB_KERNEL_COMPILER_BANNER
  # shellcheck disable=SC1090
  source "$envfile"
  local wanted_family="${KLAB_KERNEL_COMPILER_FAMILY:-}" wanted_version="${KLAB_KERNEL_COMPILER_VERSION:-}"
  local d cc base prefix=""

  # `prepare` caches a kernel.org toolchain whose resolver records the compiler
  # version requested for this build. Prefer that deterministic compiler.
  if [[ "$wanted_family" == gcc && -n "$wanted_version" && -d "$TOOLCHAINS" ]]; then
    for d in "$TOOLCHAINS"/*; do
      [[ -f "$d/.klab-resolver.env" ]] || continue
      unset KLAB_TOOLCHAIN_REQUESTED_VERSION KLAB_TOOLCHAIN_CC KLAB_TOOLCHAIN_ID KLAB_TOOLCHAIN_VERSION KLAB_TOOLCHAIN_ARCH KLAB_TOOLCHAIN_HOST
      # shellcheck disable=SC1090
      source "$d/.klab-resolver.env"
      [[ "${KLAB_TOOLCHAIN_REQUESTED_VERSION:-}" == "$wanted_version" ]] || continue
      toolchain_arch_matches "${KLAB_TOOLCHAIN_ARCH:-x86_64}" "$wanted_arch" || continue
      [[ -z "${KLAB_TOOLCHAIN_HOST:-}" || "${KLAB_TOOLCHAIN_HOST}" == "$(crosstool_host_name "$(host_arch)" 2>/dev/null || true)" ]] || continue
      cc="${KLAB_TOOLCHAIN_CC:-}"
      [[ -x "$cc" ]] || continue
      base="$(basename "$cc")"
      [[ "$base" == *-gcc ]] && prefix="${cc%gcc}"
      # Native archived-compiler wrappers invoke their sealed binutils
      # explicitly. Do not put those old binutils ahead of the host assembler,
      # which HOSTCC needs for modern instructions such as endbr64.
      if [[ -n "$prefix" ]]; then KLAB_TC_PATH="$(dirname "$cc"):$PATH"; else KLAB_TC_PATH="$PATH"; fi
      KLAB_TC_LIBRARY_PATH="$(toolchain_runtime_library_path "$d")"
      KLAB_TC_MAKE_ARGS=("CC=$cc")
      # External-module builds may rebuild host helpers. Keep those on the
      # native compiler even when kernel objects require an archived 32-bit
      # compiler whose system-header search path cannot target this host.
      KLAB_TC_MAKE_ARGS+=("HOSTCC=$(command -v gcc)" "HOSTCFLAGS=-fno-pie -no-pie -fgnu89-inline -include limits.h -include locale.h -I$build/include2" "HOSTLDFLAGS=-no-pie")
      [[ -n "$prefix" ]] && KLAB_TC_MAKE_ARGS+=("CROSS_COMPILE=$prefix")
      say "Using cached toolchain ${KLAB_TOOLCHAIN_ID:-$(basename "$d")} for upstream module build (${KLAB_TOOLCHAIN_VERSION:-?}; kernel build recorded $wanted_version)"
      return 0
    done
  fi

  # If no portable cached toolchain exists, use the host compiler only when it
  # matches the compiler family/version recorded for the kernel build.
  if [[ "$wanted_arch" == "$(host_arch)" && "$wanted_family" == gcc && -n "$wanted_version" && $(command -v gcc || true) ]]; then
    local hv
    hv="$(gcc -dumpfullversion -dumpversion 2>/dev/null | head -n1 || true)"
    if [[ "$hv" == "$wanted_version" ]]; then
      KLAB_TC_MAKE_ARGS=("CC=$(command -v gcc)")
      say "Using host GCC $hv; it matches the compiler recorded for this upstream build"
      return 0
    fi
  fi

  [[ -z "$wanted_family" || -z "$wanted_version" ]] && return 0
  die "cached upstream build was created with $wanted_family $wanted_version, but no matching cached toolchain is available and the host compiler does not match.\nOn staging run: $0 toolchain ensure upstream:<version> <profile>\nOr use '$0 prepare ...' which caches and binds a portable toolchain automatically."
}

# ---------------------------------------------------------------------------
# Stable target/test interface
# ---------------------------------------------------------------------------

validate_profile() {
  case "$1" in
    normal|debug|kasan|kcsan|lockdep) ;;
    *) die "unknown profile '$1' (expected normal, debug, kasan, kcsan, or lockdep)" ;;
  esac
}


target_bundle_env_path() {
  local target="$1" profile="$2" provider raw dir env
  provider="${target%%:*}"
  if [[ "$provider" == upstream ]]; then
    raw="${target#upstream:}"; dir="$(imported_upstream_dir "$raw" "$profile" "$ARCH")"; env="$dir/bundle.env"
  else
    parse_target "$target"; [[ -n "$KERNEL_RELEASE" ]] || return 0
    dir="$(bundle_existing_dir_for "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$ARCH" 2>/dev/null || true)"; env="$dir/bundle.env"
  fi
  [[ -f "$env" ]] && printf '%s\n' "$env"
}

target_bound_userspace() {
  local target="$1" profile="$2" env spec=""
  env="$(target_bundle_env_path "$target" "$profile" || true)"
  [[ -f "$env" ]] || return 0
  spec="$( (unset BUNDLE_GUEST_USERSPACE_SPEC BUNDLE_GUEST_USERSPACE_KIND; source "$env"; printf '%s' "${BUNDLE_GUEST_USERSPACE_SPEC:-${BUNDLE_GUEST_USERSPACE_KIND:-}}") 2>/dev/null || true)"
  case "$spec" in
    buildroot-minimal) spec=buildroot:minimal ;;
    buildroot-network) spec=buildroot:network ;;
    buildroot-ssh) spec=buildroot:ssh ;;
    busybox-static|'') ;;
  esac
  [[ -n "$spec" ]] && normalize_userspace_spec "$spec"
}

target_bound_userspace_artifact() {
  local target="$1" profile="$2" env
  env="$(target_bundle_env_path "$target" "$profile" || true)"
  [[ -f "$env" ]] || return 0
  (unset BUNDLE_GUEST_ROOTFS BUNDLE_GUEST_BUSYBOX; source "$env"; printf '%s' "${BUNDLE_GUEST_ROOTFS:-${BUNDLE_GUEST_BUSYBOX:-}}") 2>/dev/null || true
}

resolve_active_userspace() {
  local target="$1" profile="$2" requested="${3:-auto}" bound resolved artifact="" use_bound=1
  requested="$(normalize_userspace_spec "$requested")"
  if [[ "$(target_backend "$target")" != linux ]]; then
    [[ "$requested" == auto || "$requested" == busybox-static ]] || die "userspace selection '$requested' applies only to Linux targets"
    ACTIVE_USERSPACE_SPEC=busybox-static
    ACTIVE_USERSPACE_ARTIFACT=""
    return 0
  fi
  bound="$(target_bound_userspace "$target" "$profile" || true)"
  if [[ "$requested" == auto ]]; then
    if [[ -n "$bound" ]]; then
      resolved="$bound"
    elif [[ "$target" == upstream:v2.* ]]; then
      resolved=busybox-static
    else
      resolved=buildroot:minimal
    fi
  else
    resolved="$requested"
    if [[ -n "$bound" && "$bound" != "$resolved" ]]; then
      # The explicit --userspace request is authoritative when its verified
      # artifact is installed locally. The packaged binding remains the auto
      # default and is never silently substituted.
      use_bound=0
    fi
  fi
  ACTIVE_USERSPACE_SPEC="$(normalize_userspace_spec "$resolved")"
  if [[ "$ACTIVE_USERSPACE_SPEC" == native:* ]]; then
    local up ur uk ux native_kind native_provider native_release
    IFS=: read -r native_kind native_provider native_release <<<"$ACTIVE_USERSPACE_SPEC"
    IFS=: read -r up ur uk ux <<<"$target"
    [[ "$up" == "$native_provider" && -n "$uk" && -z "$ux" ]] || die "native userspace $native_provider:$native_release requires a matching $native_provider kernel target"
    [[ "$native_release" == "${ur%%@*}" ]] || die "native userspace release $native_release does not match kernel target release ${ur%%@*}"
  fi
  if (( use_bound == 1 )) && [[ -n "$bound" && "$bound" == "$resolved" ]]; then
    artifact="$(target_bound_userspace_artifact "$target" "$profile" || true)"
  fi
  ACTIVE_USERSPACE_ARTIFACT="$artifact"
  # Legacy upstream bundles may carry an older generic BusyBox binding.
  # Always select the compatibility artifact for these kernels so imported
  # bundles benefit from fixes without rewriting their immutable manifests.
  if [[ "$ACTIVE_USERSPACE_SPEC" == busybox-static && ( "$target" == upstream:v2.0.40 || "$target" == upstream:v2.2.26 ) ]]; then
    ACTIVE_USERSPACE_ARTIFACT="$(ensure_linux22_guest_busybox "$ARCH")"
  elif [[ "$ACTIVE_USERSPACE_SPEC" == busybox-static && "$target" == upstream:v2.[0-5].* ]]; then
    ACTIVE_USERSPACE_ARTIFACT="$(ensure_linux24_guest_busybox "$ARCH")"
  elif [[ "$ACTIVE_USERSPACE_SPEC" == busybox-static ]] &&
       legacy_guest_busybox_target "$target"; then
    ACTIVE_USERSPACE_ARTIFACT="$(ensure_legacy_guest_busybox "$ARCH")"
  fi
  if [[ -n "$ACTIVE_USERSPACE_ARTIFACT" ]]; then
    [[ -e "$ACTIVE_USERSPACE_ARTIFACT" ]] || die "target's bound guest userspace artifact is missing: $ACTIVE_USERSPACE_ARTIFACT"
  else
    ensure_guest_userspace "$ACTIVE_USERSPACE_SPEC" "$ARCH" >/dev/null
  fi
}

target_bound_sdk_artifact() {
  local target="$1" profile="$2" env
  env="$(target_bundle_env_path "$target" "$profile" || true)"
  [[ -f "$env" ]] || return 0
  (unset BUNDLE_GUEST_SDK; source "$env"; printf '%s' "${BUNDLE_GUEST_SDK:-}") 2>/dev/null || true
}

sdk_compiler() {
  local sdk="$1" cc
  [[ -d "$sdk/bin" ]] || die "invalid Buildroot SDK directory: $sdk"
  cc="$(find -L "$sdk/bin" -maxdepth 1 -type f -name '*-gcc' -print 2>/dev/null | head -n1 || true)"
  [[ -n "$cc" && -x "$cc" ]] || die "could not locate target GCC in Buildroot SDK: $sdk"
  printf '%s\n' "$cc"
}

resolve_buildroot_sdk_for_target() {
  local target="$1" profile="$2" spec="$3" imported brprofile sdk env brver
  spec="$(normalize_userspace_spec "$spec")"
  [[ "$spec" == buildroot:* ]] || die "guest SDK requires a Buildroot userspace (buildroot:minimal, buildroot:network, or buildroot:ssh)"
  brprofile="${spec#buildroot:}"
  imported="$(target_bound_sdk_artifact "$target" "$profile" || true)"
  if [[ -n "$imported" ]]; then [[ -d "$imported" ]] || die "bundle SDK path is missing: $imported"; printf '%s\n' "$imported"; return; fi
  if [[ "$OFFLINE" == 1 ]]; then
    sdk="$(buildroot_sdk_dir "$ARCH" "$brprofile")"
    local archive="$(buildroot_sdk_archive_path "$ARCH" "$brprofile")"
    [[ -f "$archive" && -d "$sdk" && -x "$sdk/relocate-sdk.sh" ]] || die "offline target does not include a Buildroot SDK and the verified global $brprofile SDK is missing; prepare it on staging with --with-sdk and re-import"
    printf '%s\n' "$sdk"
    return
  fi
  ensure_buildroot_sdk "$ARCH" "$brprofile"
}

cmd_build_user() {
  (($# >= 1)) || die "usage: $0 build-user <target> --source FILE [--source FILE...] [-o FILE] [--arch ARCH] [--profile PROFILE] [--userspace buildroot:minimal|buildroot:network|buildroot:ssh] [-- EXTRA_CC_ARGS...]"
  local requested="$1" target profile=normal arch="$ARCH" userspace="${KLAB_USERSPACE:-auto}" output="" static=1 sdk cc; shift
  local sources=() extra=()
  while (($#)); do
    case "$1" in
      --source) [[ $# -ge 2 ]] || die "--source needs a file"; sources+=("$2"); shift 2 ;;
      --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; arch="$(canonical_arch "$2")"; shift 2 ;;
      --profile) [[ $# -ge 2 ]] || die "--profile needs a value"; profile="$2"; shift 2 ;;
      --userspace) [[ $# -ge 2 ]] || die "--userspace needs a value"; userspace="$2"; shift 2 ;;
      -o|--output) [[ $# -ge 2 ]] || die "$1 needs a value"; output="$2"; shift 2 ;;
      --no-static) static=0; shift ;;
      --) shift; extra+=("$@"); break ;;
      *) die "unknown build-user option '$1' (pass compiler flags after --)" ;;
    esac
  done
  ((${#sources[@]} > 0)) || die "build-user requires at least one --source"
  set_active_arch "$arch"; target="$(effective_target_for_arch "$requested" "$ARCH")"; validate_profile "$profile"
  [[ "$(target_backend "$target")" == linux ]] || die "build-user currently supports Linux targets using a Buildroot SDK"
  resolve_active_userspace "$target" "$profile" "$userspace"
  [[ "$ACTIVE_USERSPACE_SPEC" == buildroot:* ]] || die "build-user requires a target prepared with Buildroot userspace"
  sdk="$(resolve_buildroot_sdk_for_target "$target" "$profile" "$ACTIVE_USERSPACE_SPEC")"; cc="$(sdk_compiler "$sdk")"
  local src; for src in "${sources[@]}"; do [[ -f "$src" ]] || die "source file not found: $src"; done
  [[ -n "$output" ]] || { mkdir -p "$ARTIFACTS/user"; output="$ARTIFACTS/user/$(basename "${sources[0]%.*}")__${ARCH}"; }
  mkdir -p "$(dirname "$output")"
  local cmd=("$cc"); (( static == 1 )) && cmd+=(-static); cmd+=("${sources[@]}" -o "$output" "${extra[@]}")
  say "Building guest userspace test program for $ARCH using Buildroot ${ACTIVE_USERSPACE_SPEC#buildroot:} SDK"
  "${cmd[@]}" || die "guest userspace compilation failed"
  printf '%s\n' "$output"
}

resolve_upstream_build_dir() {
  local raw="$1" profile="$2" arch="$(canonical_arch "${3:-$ARCH}")" version dir=""
  version="$(normalize_version "$raw")"
  if [[ "$version" == mainline ]]; then
    dir="$(find "$BUILDS" -mindepth 1 -maxdepth 1 -type d -name "mainline-*__${arch}__${profile}" -printf '%T@\t%p\n' 2>/dev/null | sort -nr | head -n1 | cut -f2-)"
    if [[ -z "$dir" && "$arch" == x86_64 ]]; then
      dir="$(find "$BUILDS" -mindepth 1 -maxdepth 1 -type d -name "mainline-*__${profile}" -printf '%T@\t%p\n' 2>/dev/null | sort -nr | head -n1 | cut -f2-)"
    fi
  else
    dir="$BUILDS/${version#v}__${arch}__${profile}"
    if [[ ! -d "$dir" && "$arch" == x86_64 && -d "$BUILDS/${version#v}__${profile}" ]]; then dir="$BUILDS/${version#v}__${profile}"; fi
    [[ -d "$dir" ]] || dir=""
  fi
  [[ -n "$dir" ]] && printf '%s\n' "$dir"
}

upstream_target_ready() {
  local raw="$1" profile="$2" arch="$(canonical_arch "${3:-$ARCH}")" imported built image_rel
  imported="$(imported_upstream_dir "$raw" "$profile" "$arch")"
  [[ -f "$imported/bundle.env" ]] && return 0
  built="$(resolve_upstream_build_dir "$raw" "$profile" "$arch" || true)"
  image_rel="$(linux_kernel_image_rel_for_build "$built" "$arch")"
  [[ -n "$built" && -f "$built/$image_rel" ]]
}

cmd_targets() {
  printf '%-48s %-8s %-9s %-9s %-10s %-18s %s\n' TARGET BACKEND ARCH PROFILE STATE USERSPACE TOOLCHAIN
  printf '%-48s %-8s %-9s %-9s %-10s %-18s %s\n' '------' '-------' '----' '-------' '-----' '---------' '---------'
  local d base profile raw env target tc backend arch stem us
  if [[ -d "$BUILDS" ]]; then
    while IFS= read -r d; do
      [[ -n "$d" ]] || continue
      base="$(basename "$d")"
      arch="$(cat "$d/.klab-arch" 2>/dev/null || echo x86_64)"; arch="$(canonical_arch "$arch")"
      profile="${base##*__}"
      stem="${base%__${profile}}"; stem="${stem%__${arch}}"
      if [[ "$stem" == mainline-* ]]; then raw=mainline; else raw="v$stem"; fi
      printf '%-48s %-8s %-9s %-9s %-10s %-18s %s\n' "upstream:$raw" linux "$arch" "$profile" built select-at-run "$( [[ -f "$d/.klab-compiler.env" ]] && echo recorded || echo host )"
    done < <(find "$BUILDS" -mindepth 1 -maxdepth 1 -type d -name '*__*' -print 2>/dev/null | sort)
  fi
  if [[ -d "$KERNELS/upstream" ]]; then
    while IFS= read -r env; do
      [[ -n "$env" ]] || continue
      reset_bundle_toolchain_vars; unset BUNDLE_ARCH BUNDLE_PROFILE BUNDLE_UPSTREAM_VERSION
      # shellcheck disable=SC1090
      source "$env"
      arch="$(canonical_arch "${BUNDLE_ARCH:-x86_64}")"; profile="${BUNDLE_PROFILE:-$(basename "$(dirname "$env")")}"; raw="${BUNDLE_UPSTREAM_VERSION:-?}"
      [[ "$raw" == mainline || "$raw" == master ]] || raw="v${raw#v}"
      tc="${BUNDLE_TOOLCHAIN_ID:-none}"; us="${BUNDLE_GUEST_USERSPACE_SPEC:-busybox-static}"
      printf '%-48s %-8s %-9s %-9s %-10s %-18s %s\n' "upstream:$raw" linux "$arch" "$profile" imported "$us" "$tc"
    done < <(find "$KERNELS/upstream" -type f -name bundle.env -print 2>/dev/null | sort)
  fi
  if [[ -d "$KERNELS" ]]; then
    while IFS= read -r env; do
      [[ -n "$env" ]] || continue; case "$env" in "$KERNELS/upstream/"*) continue ;; esac
      reset_bundle_toolchain_vars; unset BUNDLE_TARGET_ID BUNDLE_BACKEND BUNDLE_CAPABILITIES BUNDLE_ARCH
      # shellcheck disable=SC1090
      source "$env"
      target="${BUNDLE_TARGET_ID:-${BUNDLE_PROVIDER}:${BUNDLE_DISTRO_RELEASE}:${BUNDLE_KERNEL_RELEASE}}"
      backend="${BUNDLE_BACKEND:-$(backend_for_provider "$BUNDLE_PROVIDER")}"; tc="${BUNDLE_TOOLCHAIN_ID:-${BUNDLE_DISTRO_TOOLCHAIN_ID:-none}}"; arch="$(canonical_arch "${BUNDLE_ARCH:-x86_64}")"; us="${BUNDLE_GUEST_USERSPACE_SPEC:--}"
      printf '%-48s %-8s %-9s %-9s %-10s %-18s %s\n' "$target" "$backend" "$arch" '-' imported "$us" "$tc"
    done < <(find "$KERNELS" -type f -name bundle.env -print 2>/dev/null | sort)
  fi
}

cmd_info_stable() {
  (($# >= 1)) || die "usage: $0 info <target> [--arch ARCH] [--profile PROFILE]"
  local requested="$1" target profile=normal arch="$ARCH" raw dir build; shift
  while (($#)); do
    case "$1" in
      --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; arch="$(canonical_arch "$2")"; shift 2 ;;
      --profile) [[ $# -ge 2 ]] || die "--profile needs a value"; profile="$2"; shift 2 ;;
      *) die "unknown info option '$1'" ;;
    esac
  done
  set_active_arch "$arch"; target="$(effective_target_for_arch "$requested" "$ARCH")"; validate_profile "$profile"
  if [[ "$target" == upstream:* ]]; then
    raw="${target#upstream:}"; [[ -n "$raw" && "$raw" != *:* ]] || die "upstream target syntax: upstream:v6.6"
    dir="$(imported_upstream_dir "$raw" "$profile" "$ARCH")"
    if [[ -f "$dir/bundle.env" ]]; then
      reset_bundle_toolchain_vars; unset BUNDLE_ARCH
      # shellcheck disable=SC1090
      source "$dir/bundle.env"
      cat <<EOF
Target:          $requested
Backend:         linux
Architecture:    ${BUNDLE_ARCH:-$ARCH}
Profile:         $profile
State:           imported
Kernel image:    $BUNDLE_KERNEL_IMAGE
Source tree:     $BUNDLE_SOURCE_DIR
Build tree:      $BUNDLE_BUILD_DIR
Guest userspace: ${BUNDLE_GUEST_USERSPACE_SPEC:-busybox-static}
Guest artifact:  ${BUNDLE_GUEST_ROOTFS:-${BUNDLE_GUEST_BUSYBOX:-$(guest_busybox_path "$ARCH")}}
Toolchain bound: $( [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 ]] && echo yes || echo no )
Toolchain ID:    ${BUNDLE_TOOLCHAIN_ID:-none}
EOF
      return
    fi
    build="$(resolve_upstream_build_dir "$raw" "$profile" "$ARCH" || true)"
    [[ -n "$build" ]] || die "target is not ready locally: $requested / $ARCH / $profile"
    cat <<EOF
Target:          $requested
Backend:         linux
Architecture:    $ARCH
Profile:         $profile
State:           built-local
Kernel image:    $build/$(linux_kernel_image_rel_for_build "$build" "$ARCH")
Source tree:     $(source_for_cached_build "$build" "$raw")
Build tree:      $build
Guest userspace: selectable at run time (busybox-static, buildroot:minimal, buildroot:network, or buildroot:ssh)
EOF
    [[ -f "$build/.klab-compiler.env" ]] && { echo 'Compiler record:'; sed 's/^/  /' "$build/.klab-compiler.env"; }
    return
  fi
  [[ "$profile" == normal ]] || die "--profile applies only to upstream targets"
  cmd_info "$target"
}

stable_target_ready_or_die() {
  local target="$1" profile="$2" provider raw d
  validate_profile "$profile"; provider="${target%%:*}"
  if [[ "$provider" == upstream ]]; then
    raw="${target#upstream:}"; [[ -n "$raw" && "$raw" != *:* ]] || die "upstream target syntax: upstream:v6.6"
    upstream_target_ready "$raw" "$profile" "$ARCH" || {
      if [[ "$OFFLINE" == 1 ]]; then die "target is not imported locally: $target / $ARCH / $profile"; else die "target is not built locally: $target / $ARCH / $profile\nRun '$0 prepare $target --arch $ARCH --profile $profile' first."; fi
    }
  else
    [[ "$profile" == normal ]] || die "--profile applies only to upstream targets"
    parse_target "$target"; [[ -n "$KERNEL_RELEASE" ]] || die "target needs a release/build selector"
    d="$(bundle_existing_dir_for "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$ARCH" 2>/dev/null || true)"
    [[ -n "$d" && -f "$d/bundle.env" ]] || die "target is not imported/prepared locally: $target [$ARCH]"
  fi
}

stable_kernel_image() {
  local target="$1" profile="$2" provider raw dir build
  stable_target_ready_or_die "$target" "$profile"; provider="${target%%:*}"
  if [[ "$provider" == upstream ]]; then
    raw="${target#upstream:}"; dir="$(imported_upstream_dir "$raw" "$profile" "$ARCH")"
    if [[ -f "$dir/bundle.env" ]]; then reset_bundle_toolchain_vars; source "$dir/bundle.env"; printf '%s\n' "$BUNDLE_KERNEL_IMAGE"
    else build="$(resolve_upstream_build_dir "$raw" "$profile" "$ARCH")"; printf '%s\n' "$build/$(linux_kernel_image_rel_for_build "$build" "$ARCH")"; fi
  else bundle_load "$target"; printf '%s\n' "$BUNDLE_KERNEL_IMAGE"; fi
}

build_linux24_external_modules() {
  local build="$1" module_dir="$2" cc="" arg c out
  for arg in "${KLAB_TC_MAKE_ARGS[@]}"; do
    case "$arg" in CC=*) cc="${arg#CC=}" ;; esac
  done
  [[ -n "$cc" && -x "$cc" ]] || die "Linux 2.4 module build has no sealed compiler"
  mapfile -t legacy_sources < <(find "$module_dir" -maxdepth 1 -type f -name '*.c' -print | sort)
  ((${#legacy_sources[@]} > 0)) || die "Linux 2.4 module directory contains no C sources"
  for c in "${legacy_sources[@]}"; do
    out="${c%.c}.o"
    PATH="$KLAB_TC_PATH" LD_LIBRARY_PATH="${KLAB_TC_LIBRARY_PATH:-${LD_LIBRARY_PATH:-}}" "$cc"       -D__KERNEL__ -DMODULE -I"$build/include"       -Wall -Wstrict-prototypes -Wno-trigraphs -O2       -fno-builtin-strpbrk -fno-builtin-sprintf -fomit-frame-pointer       -pipe -mpreferred-stack-boundary=2 -march=i686 -c "$c" -o "$out"
  done
}

stable_build_module() {
  local target="$1" profile="$2" module_dir="$3" provider raw dir job build source karch
  stable_target_ready_or_die "$target" "$profile"
  if [[ "$(target_backend "$target")" == freebsd ]]; then [[ "$profile" == normal ]] || die "FreeBSD targets do not use Linux profiles"; build_freebsd_module "$target" "$module_dir"; return; fi
  provider="${target%%:*}"; karch="$(linux_karch "$ARCH")"
  if [[ "$provider" == upstream ]]; then
    raw="${target#upstream:}"; dir="$(imported_upstream_dir "$raw" "$profile" "$ARCH")"
    if [[ -f "$dir/bundle.env" ]]; then
      reset_bundle_toolchain_vars; source "$dir/bundle.env"; [[ -d "$BUNDLE_SOURCE_DIR" && -d "$BUNDLE_BUILD_DIR" ]] || die "imported upstream bundle is incomplete: $dir"
      karch="$(linux_karch_for_source "$ARCH" "$BUNDLE_SOURCE_DIR")"
      job="$(copy_module_job "$target:$ARCH:$profile" "$module_dir")"; say "Building external module against imported upstream $raw [$ARCH/$profile]"
      prepare_bound_toolchain
      if [[ "$target" == upstream:v2.[0-5].* ]]; then
        build_linux24_external_modules "$BUNDLE_BUILD_DIR" "$job/module"
      else
        local ext_assignment
        ext_assignment="$(external_module_make_assignment "$BUNDLE_SOURCE_DIR" "$job/module")"
        if [[ "$ext_assignment" == M=* ]]; then
          bound_make ARCH="$karch" -s -C "$BUNDLE_SOURCE_DIR" O="$BUNDLE_BUILD_DIR" "$ext_assignment" clean || true
        fi
        bound_make ARCH="$karch" -C "$BUNDLE_SOURCE_DIR" O="$BUNDLE_BUILD_DIR" "$ext_assignment" -j"$JOBS" modules
      fi
      MODULE_JOB="$job"
    else
      build="$(resolve_upstream_build_dir "$raw" "$profile" "$ARCH")"; source="$(source_for_cached_build "$build" "$raw")"; job="$(copy_module_job "$target:$ARCH:$profile" "$module_dir")"
      karch="$(linux_karch_for_build "$build" "$ARCH")"
      say "Building external module against cached upstream $raw [$ARCH/$profile]"
      prepare_cached_upstream_toolchain "$build"
      if [[ "$target" == upstream:v2.[0-5].* ]]; then
        build_linux24_external_modules "$build" "$job/module"
      else
        local ext_assignment
        ext_assignment="$(external_module_make_assignment "$source" "$job/module")"
        if [[ "$ext_assignment" == M=* ]]; then
          PATH="$KLAB_TC_PATH" LD_LIBRARY_PATH="${KLAB_TC_LIBRARY_PATH:-${LD_LIBRARY_PATH:-}}" make "${KLAB_TC_MAKE_ARGS[@]}" ARCH="$karch" -s -C "$source" O="$build" "$ext_assignment" clean || true
        fi
        PATH="$KLAB_TC_PATH" LD_LIBRARY_PATH="${KLAB_TC_LIBRARY_PATH:-${LD_LIBRARY_PATH:-}}" make "${KLAB_TC_MAKE_ARGS[@]}" ARCH="$karch" -C "$source" O="$build" "$ext_assignment" -j"$JOBS" modules
      fi
      MODULE_JOB="$job"
    fi
  else build_external_module_bundle "$target" "$module_dir"; fi
  if [[ "$target" == upstream:v2.[0-5].* ]]; then
    mapfile -t MODULE_FILES < <(find "$MODULE_JOB/module" -maxdepth 1 -type f -name '*.o' -print | sort)
    ((${#MODULE_FILES[@]} > 0)) || die "no Linux 2.4 .o modules were produced for $target [$ARCH]"
  else
    mapfile -t MODULE_FILES < <(find "$MODULE_JOB/module" -type f -name '*.ko' -print | sort)
    ((${#MODULE_FILES[@]} > 0)) || die "no .ko files were produced for $target [$ARCH]"
  fi
}

run_linux20_persistent_test() {
  local target="$1" profile="$2" test_script="$3" session module remote command rc=1
  ((${#MODULE_FILES[@]} == 1)) || die "Linux 2.0 persistent test requires exactly one module object"
  module="${MODULE_FILES[0]}"
  remote="/tmp/$(basename "$module")"
  session="t20-$$-${RANDOM:-0}"
  command="/sbin/linux20/insmod '$remote' || exit \$?; echo KLAB_INSMOD_LINUX20; printf 7 > /tmp/klab_coord_loaded; . /tmp/klab-test.sh; test_rc=\$?; rm -f /tmp/klab_coord_loaded; /sbin/linux20/rmmod klab_coord || exit \$?; echo KLAB_RMMOD_LINUX20; exit \$test_rc"
  if cmd_boot_session "$target" --arch "$ARCH" --profile "$profile" --userspace "${ACTIVE_USERSPACE_SPEC:-busybox-static}" --name "$session" --preload "$module" "$remote" --preload "$test_script" /tmp/klab-test.sh >/dev/null; then
    load_session_env "$session"
    session_rpc_exec "$SESSION_CONTROL" "$command" 120 && rc=0 || rc=$?
  fi
  if [[ -f "$(session_dir "$session")/session.env" ]]; then
    cmd_stop_session "$session" >/dev/null 2>&1 || true
  fi
  return "$rc"
}

run_stable_target_test() {
  local target="$1" profile="$2" module_dir="$3" test_script="$4" crashdump="${5:-0}" panic_on_warn="${6:-0}" provider key initrd kernel
  if [[ "$(target_backend "$target")" == freebsd ]]; then [[ "$profile" == normal ]] || die "FreeBSD targets do not use Linux profiles"; run_freebsd_target_test "$target" "$module_dir" "$test_script" "$crashdump" "$panic_on_warn"; return; fi
  stable_build_module "$target" "$profile" "$module_dir"; provider="${target%%:*}"; key="$(printf '%s_%s_%s' "$target" "$ARCH" "$profile" | tr ':@/' '___')"; kernel="$(stable_kernel_image "$target" "$profile")"
  if [[ "$target" == upstream:v2.0.40 ]]; then
    ACTIVE_USERSPACE_SPEC=busybox-static
    ACTIVE_USERSPACE_ARTIFACT="$(ensure_linux24_guest_busybox "$ARCH")"
    run_linux20_persistent_test "$target" "$profile" "$test_script"
    return
  fi
  if [[ "$provider" == upstream && "$target" == upstream:v2.[0-5].* && -z "${ACTIVE_USERSPACE_ARTIFACT:-}" ]]; then
    ACTIVE_USERSPACE_SPEC=busybox-static
    ACTIVE_USERSPACE_ARTIFACT="$(ensure_linux24_guest_busybox "$ARCH")"
  elif [[ "$provider" == upstream && -z "${ACTIVE_USERSPACE_ARTIFACT:-}" ]] &&
       legacy_guest_busybox_target "$target"; then
    ACTIVE_USERSPACE_SPEC=busybox-static
    ACTIVE_USERSPACE_ARTIFACT="$(ensure_legacy_guest_busybox "$ARCH")"
  fi
  if [[ "$provider" == upstream ]]; then initrd="$(make_initramfs "$key" "$test_script" "${MODULE_FILES[@]}")" || die "failed to create initramfs for $key"; else initrd="$(make_initramfs_bundle "$target" "$key" "$test_script" "${MODULE_FILES[@]}")" || die "failed to create distro initramfs for $target"; fi
  run_qemu_image "$key" "$kernel" "$initrd" "$crashdump" "$panic_on_warn" "$target" "$profile"
}

cmd_build_module_stable() {
  (($# >= 1)) || die "usage: $0 build-module <target> --module DIR [--arch ARCH] [--profile PROFILE] [-o DIR]"
  local requested="$1" target; shift
  local module_dir="" profile=normal output="" arch="$ARCH"
  while (($#)); do
    case "$1" in
      --module|-m) [[ $# -ge 2 ]] || die "$1 needs a directory"; module_dir="$2"; shift 2 ;;
      --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; arch="$(canonical_arch "$2")"; shift 2 ;;
      --profile|-p) [[ $# -ge 2 ]] || die "$1 needs a profile"; profile="$2"; shift 2 ;;
      -o|--output) [[ $# -ge 2 ]] || die "$1 needs a directory"; output="$2"; shift 2 ;;
      *) die "unknown build-module option '$1'" ;;
    esac
  done
  [[ -n "$module_dir" ]] || die "build-module requires --module DIR"
  set_active_arch "$arch"; target="$(effective_target_for_arch "$requested" "$ARCH")"; validate_profile "$profile"
  stable_build_module "$target" "$profile" "$module_dir"
  local safe m; safe="$(printf '%s' "$requested" | tr ':@/' '___')"
  [[ -n "$output" ]] || output="$ARTIFACTS/$safe/$ARCH/$profile"
  mkdir -p "$output"; rm -f "$output"/*.ko "$output/TARGET" 2>/dev/null || true
  for m in "${MODULE_FILES[@]}"; do cp "$m" "$output/"; done
  printf 'target=%s\narch=%s\nprofile=%s\n' "$requested" "$ARCH" "$profile" > "$output/TARGET"
  say "Module artifacts: $output"
  find "$output" -maxdepth 1 -type f \( -name '*.ko' -o -name '*.o' \) -print | sort
}

session_name_validate() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || die "session names may contain only letters, digits, '.', '_' and '-'"
  ((${#1} <= 40)) || die "session name is too long (maximum 40 characters)"
}

cmd_boot_session() {
  (($# >= 1)) || die "usage: $0 boot <target> [--arch ARCH] [--profile PROFILE] [--userspace SPEC] [--name SESSION] [--ssh-auth key|password|none] [--ssh-key PRIVATE_KEY] [--ssh-password PASSWORD] [--ssh-bind 127.0.0.1|0.0.0.0] [--ssh-port PORT] [--net-link ID MCAST:PORT CIDR MAC IFACE [--net-capture FILE] [--net-delay-us USEC]]... [--preload LOCAL REMOTE]... [--crashdump] [--panic-on-warn]"
  local requested="$1" target; shift
  local profile=normal name="" crashdump=0 panic_on_warn=0 arch="$ARCH" userspace="${KLAB_USERSPACE:-auto}" net_bus="" net_ip="" net_mac="" net_if="eth0" ssh_auth=off ssh_key="" ssh_pub="" ssh_password="${KLAB_SSH_PASSWORD:-}" ssh_bind=127.0.0.1 ssh_port=2222 ssh_mac="52:54:00:12:34:56" ssh_shadow_hash="" kernel key dir initrd sock proxy qmp console pidfile hash base_hash pid relay_pid i append last_net=-1 legacy_iso=""
  local -a net_ids=() net_buses=() net_ips=() net_macs=() net_ifs=() net_caps=() net_delays=() preload_local=() preload_remote=()
  while (($#)); do
    case "$1" in
      --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; arch="$(canonical_arch "$2")"; shift 2 ;;
      --profile|-p) [[ $# -ge 2 ]] || die "$1 needs a profile"; profile="$2"; shift 2 ;;
      --userspace) [[ $# -ge 2 ]] || die "--userspace needs a value"; userspace="$2"; shift 2 ;;
      --name|-n) [[ $# -ge 2 ]] || die "$1 needs a session name"; name="$2"; shift 2 ;;
      --ssh-auth) [[ $# -ge 2 ]] || die "--ssh-auth needs key, password, or none"; ssh_auth="$2"; shift 2 ;;
      --ssh-key) [[ $# -ge 2 ]] || die "--ssh-key needs a private key file"; ssh_key="$2"; [[ "$ssh_auth" == off || "$ssh_auth" == key ]] || die "--ssh-key conflicts with --ssh-auth $ssh_auth"; ssh_auth=key; shift 2 ;;
      --ssh-password) [[ $# -ge 2 ]] || die "--ssh-password needs a value"; ssh_password="$2"; [[ "$ssh_auth" == off || "$ssh_auth" == password ]] || die "--ssh-password conflicts with --ssh-auth $ssh_auth"; ssh_auth=password; shift 2 ;;
      --ssh-bind) [[ $# -ge 2 ]] || die "--ssh-bind needs 127.0.0.1 or 0.0.0.0"; ssh_bind="$2"; shift 2 ;;
      --ssh-port) [[ $# -ge 2 ]] || die "--ssh-port needs a host TCP port"; ssh_port="$2"; shift 2 ;;
      --net-bus) [[ $# -ge 2 ]] || die "--net-bus needs MCAST:PORT"; net_bus="$2"; shift 2 ;;
      --net-ip) [[ $# -ge 2 ]] || die "--net-ip needs CIDR"; net_ip="$2"; shift 2 ;;
      --net-mac) [[ $# -ge 2 ]] || die "--net-mac needs MAC"; net_mac="$2"; shift 2 ;;
      --net-if) [[ $# -ge 2 ]] || die "--net-if needs interface"; net_if="$2"; shift 2 ;;
      --preload)
        [[ $# -ge 3 ]] || die "--preload needs LOCAL REMOTE"
        [[ -f "$2" ]] || die "--preload local file not found: $2"
        [[ "$3" == /* && "$3" != *$'\n'* && "$3" != *'/../'* && "$3" != */.. ]] || die "--preload remote path must be absolute and may not contain .."
        preload_local+=("$(readlink -f "$2")"); preload_remote+=("$3"); shift 3 ;;
      --net-link)
        [[ $# -ge 6 ]] || die "--net-link needs ID MCAST:PORT CIDR MAC IFACE"
        net_ids+=("$2"); net_buses+=("$3"); net_ips+=("$4"); net_macs+=("$5"); net_ifs+=("$6"); net_caps+=(""); net_delays+=(0); last_net=$((${#net_ids[@]}-1)); shift 6 ;;
      --net-capture)
        [[ $# -ge 2 && $last_net -ge 0 ]] || die "--net-capture must follow --net-link and needs FILE"
        net_caps[$last_net]="$2"; shift 2 ;;
      --net-delay-us)
        [[ $# -ge 2 && $last_net -ge 0 ]] || die "--net-delay-us must follow --net-link and needs USEC"
        [[ "$2" =~ ^[0-9]+$ ]] || die "--net-delay-us must be a non-negative integer"
        net_delays[$last_net]="$2"; shift 2 ;;
      --crashdump) crashdump=1; shift ;;
      --panic-on-warn) panic_on_warn=1; shift ;;
      *) die "unknown boot option '$1'" ;;
    esac
  done
  set_active_arch "$arch"; target="$(effective_target_for_arch "$requested" "$ARCH")"
  stable_target_ready_or_die "$target" "$profile"
  case "$ssh_auth" in off|key|password|none) ;; *) die "--ssh-auth must be key, password, or none" ;; esac
  [[ "$ssh_bind" == 127.0.0.1 || "$ssh_bind" == 0.0.0.0 ]] || die "--ssh-bind must be 127.0.0.1 or 0.0.0.0"
  if [[ "$ssh_auth" != off ]]; then
    [[ "$ssh_port" =~ ^[0-9]+$ ]] && (( ssh_port >= 1 && ssh_port <= 65535 )) || die "--ssh-port must be between 1 and 65535"
    if [[ "$(target_backend "$target")" != freebsd ]]; then
      local normalized_ssh_userspace
      normalized_ssh_userspace="$(normalize_userspace_spec "$userspace")"
      if [[ "$normalized_ssh_userspace" != auto ]]; then
        [[ "$normalized_ssh_userspace" == buildroot:* || "$normalized_ssh_userspace" == native:* ||
           ( "$normalized_ssh_userspace" == busybox-static && ( "$target" == upstream:v2.0.40 || "$target" == upstream:v2.2.26 ) ) ]] ||
          die "SSH requires Buildroot, native:PROVIDER:RELEASE, or the sealed Linux 2.0/2.2 compatibility userspace"
      fi
    elif [[ "$ssh_auth" != key ]]; then
      die "FreeBSD SSH currently requires --ssh-auth key"
    fi
  fi
  if [[ "$ssh_auth" == key ]]; then
    [[ -n "$ssh_key" && -f "$ssh_key" ]] || die "--ssh-auth key requires --ssh-key PRIVATE_KEY"
    [[ -z "$ssh_password" ]] || die "key authentication cannot be combined with --ssh-password or KLAB_SSH_PASSWORD"
    have ssh-keygen || die "--ssh-key requires ssh-keygen on the host"
    ssh_key="$(readlink -f "$ssh_key")"
  elif [[ "$ssh_auth" == password ]]; then
    [[ -n "$ssh_password" ]] || die "--ssh-auth password requires --ssh-password or KLAB_SSH_PASSWORD"
    [[ -z "$ssh_key" ]] || die "password authentication cannot be combined with --ssh-key"
    have openssl || die "password authentication requires openssl on the host"
    ssh_shadow_hash="$(printf '%s' "$ssh_password" | openssl passwd -6 -stdin)" || die "could not hash SSH password"
    ssh_password=""
  elif [[ "$ssh_auth" == none ]]; then
    [[ -z "$ssh_key" && -z "$ssh_password" ]] || die "passwordless authentication cannot be combined with a key or password"
  fi
  resolve_active_userspace "$target" "$profile" "$userspace"
  [[ "$crashdump" == 1 ]] && validate_crashdump_format
  if [[ "$(target_backend "$target")" == freebsd ]]; then
    ((${#preload_local[@]} == 0)) || die "--preload is currently supported for Linux initramfs guests"
    boot_freebsd_session "$target" "$profile" "$name" "$crashdump" "$panic_on_warn"
    return
  fi
  KLAB_SESSION_PRELOAD_LOCAL=("${preload_local[@]}")
  KLAB_SESSION_PRELOAD_REMOTE=("${preload_remote[@]}")
  base_hash="$(printf '%s\n' "$LAB_HOME|$target|$ARCH|$profile" | sha256sum | cut -c1-12)"
  [[ -n "$name" ]] || name="k$base_hash"
  session_name_validate "$name"
  hash="$(printf '%s\n' "$LAB_HOME|$target|$ARCH|$profile|$name" | sha256sum | cut -c1-12)"
  dir="$(session_dir "$name")"
  if [[ -f "$dir/pid" ]] && kill -0 "$(cat "$dir/pid")" 2>/dev/null; then die "session '$name' is already running"; fi
  rm -rf "$dir"; mkdir -p "$dir" "$SESSIONS" "$CRASHES"
  sock="/tmp/klab-${UID:-$(id -u)}-$hash.sock"
  qmp="/tmp/klab-qmp-${UID:-$(id -u)}-$hash.sock"
  rm -f "$sock" "$qmp"
  console="$dir/console.log"
  pidfile="$dir/pid"
  kernel="$(stable_kernel_image "$target" "$profile")"
  if [[ "$ARCH" == i386 && ( "$target" == upstream:v2.0.40 || "$target" == upstream:v2.2.26 ) ]]; then
    legacy_iso="$(cd "$(dirname "$kernel")/../../.." && pwd)/.klab-linux16-boot.iso"
    [[ -f "$legacy_iso" ]] || die "$target boot requires the packaged linux16 ISO: $legacy_iso"
  fi
  key="session_${name}"
  if [[ "$ssh_auth" == key ]]; then
    ssh_pub="$dir/authorized_key.pub"
    ssh-keygen -y -f "$ssh_key" > "$ssh_pub" 2>"$dir/ssh-keygen-error.log" || die "could not derive a public key from $ssh_key"
  fi
  local include_network_modules=0
  [[ -n "$net_bus" || ${#net_ids[@]} -gt 0 || "$ssh_auth" != off ]] && include_network_modules=1
  initrd="$(make_session_initramfs "$key" "$target" "$ssh_pub" "$include_network_modules" "$([[ "$ssh_auth" != off ]] && echo 1 || echo 0)")" || die "failed to create session initramfs for $target [$ARCH]"
  if legacy_block_initrd_target "$target"; then
    append="console=$(linux_session_console "$ARCH" "$target") root=/dev/ram0 rw init=/init panic=0 oops=panic loglevel=7"
  else
    append="$(qemu_console_append "$ARCH") rdinit=/init panic=0 oops=panic loglevel=7"
  fi
  [[ "$panic_on_warn" == 1 ]] && append+=' panic_on_warn=1'

  if [[ -n "$net_bus" || -n "$net_ip" || -n "$net_mac" ]]; then
    ((${#net_ids[@]} == 0)) || die "legacy --net-bus/--net-ip/--net-mac options cannot be combined with --net-link"
    [[ -n "$net_bus" && -n "$net_ip" && -n "$net_mac" ]] || die "--net-bus, --net-ip and --net-mac must be supplied together"
    net_ids+=(net0); net_buses+=("$net_bus"); net_ips+=("$net_ip"); net_macs+=("$net_mac"); net_ifs+=("$net_if"); net_caps+=(""); net_delays+=(0)
  fi

  say "Booting persistent session '$name' for $target [$ARCH]"
  local qemu; qemu="$(require_qemu_arch "$ARCH")"
  local accel=() control=() network=() linkargs=() qmem qcpus; mapfile -t accel < <(qemu_accel_args "$ARCH"); mapfile -t control < <(qemu_control_args "$ARCH" "$sock")
  qmem="$(qemu_memory_for_arch "$ARCH")"; qcpus="$(qemu_cpus_for_arch "$ARCH")"
  [[ "$ACTIVE_USERSPACE_SPEC" == native:* ]] && qmem="$NATIVE_MEMORY"
  if [[ ( "$target" == upstream:v2.* || "$target" == upstream:v3.[0-9] || "$target" == upstream:v3.1[01] ) && ( "$ARCH" == x86_64 || "$ARCH" == i386 ) ]]; then
    if [[ "$target" == upstream:v2.6.16 && "$ARCH" == x86_64 ]] && qemu_kvm_compatible "$ARCH"; then mapfile -t accel < <(qemu_accel_args "$ARCH"); elif [[ "$target" == upstream:v2.0.40 && "$ARCH" == i386 ]]; then accel=(-accel tcg -cpu pentium3); elif [[ "$target" == upstream:v2.2.26 && "$ARCH" == i386 ]]; then accel=(-accel tcg -cpu pentium3); elif [[ "$ARCH" == i386 ]]; then accel=(-accel tcg -cpu qemu32); else accel=(-accel tcg -cpu qemu64); fi
    qmem=256M; qcpus=1
  fi
  if ((${#net_ids[@]})); then
    for ((i=0;i<${#net_ids[@]};i++)); do
      mapfile -t linkargs < <(qemu_network_link_args "$ARCH" "${net_buses[$i]}" "${net_macs[$i]}" "klabnet$i" "klabnic$i" "${net_caps[$i]}" "${net_delays[$i]}" "$target")
      network+=("${linkargs[@]}")
    done
  else
    network=(-net none)
  fi
  if [[ "$ssh_auth" != off ]]; then
    local ssh_dev
    ssh_dev="$(qemu_net_device_for_target "$ARCH" "$target")" || die "SSH networking is unavailable for architecture $ARCH"
    ((${#net_ids[@]})) || network=()
    network+=(-netdev "user,id=klabssh,hostfwd=tcp:${ssh_bind}:${ssh_port}-10.0.2.15:22" -device "$ssh_dev,netdev=klabssh,mac=$ssh_mac,id=klabsshdev")
  fi
  local -a boot_media=()
  if [[ -n "$legacy_iso" ]]; then
    legacy_iso="$dir/runtime-linux16.iso"
    make_legacy_linux16_runtime_iso "$kernel" "$initrd" "$target" "$legacy_iso"
    boot_media=(-cdrom "$legacy_iso" -boot d)
  else
    boot_media=(-kernel "$kernel" -initrd "$initrd" -append "$append")
  fi
  local -a session_serial=(-serial "file:$console" "${control[@]}")
  # This imported 2.6.22 x86_64 build enumerates QEMU's first 8250 UART as
  # ttyS1 and its second as ttyS0. Keep the guest ABI (console ttyS0, control
  # ttyS1) stable by reversing only the host-side serial argument order.
  if [[ "$target" == upstream:v2.6.22 && "$ARCH" == x86_64 ]]; then
    session_serial=("${control[@]}" -serial "file:$console")
  fi
  "$qemu" "${accel[@]}" -machine "$(qemu_machine_for_arch "$ARCH")" -m "$qmem" -smp "$qcpus" \
    "${boot_media[@]}" \
    -display none "${network[@]}" "${session_serial[@]}" \
    -qmp "unix:$qmp,server=on,wait=off" \
    -monitor none -no-reboot -daemonize -pidfile "$pidfile" \
    2>"$dir/qemu-error.log" || die "QEMU failed to start; see $dir/qemu-error.log"
  [[ -f "$pidfile" ]] || die "QEMU did not create a pid file"
  pid="$(cat "$pidfile")"
  : > "$dir/network-links.tsv"
  if ((${#net_ids[@]})); then
    for ((i=0;i<${#net_ids[@]};i++)); do printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${net_ids[$i]}" "${net_buses[$i]}" "${net_ips[$i]}" "${net_macs[$i]}" "${net_ifs[$i]}" "klabnic$i" "${net_caps[$i]}" "${net_delays[$i]}" >> "$dir/network-links.tsv"; done
    net_bus="${net_buses[0]}"; net_ip="${net_ips[0]}"; net_mac="${net_macs[0]}"; net_if="${net_ifs[0]}"
  fi
  proxy="${sock%.sock}-proxy.sock"
  relay_pid="$(start_serial_relay "$sock" "$proxy" "$dir/control-relay.log")" || die "Linux control relay failed to start; see $dir/control-relay.log"
  printf 'SESSION_TARGET=%q\nSESSION_BACKEND=linux\nSESSION_ARCH=%q\nSESSION_PROFILE=%q\nSESSION_USERSPACE=%q\nSESSION_KERNEL=%q\nSESSION_CONTROL=%q\nSESSION_CONTROL_UPSTREAM=%q\nSESSION_CONTROL_RELAY_PID=%q\nSESSION_CONTROL_MODE=%q\nSESSION_QMP=%q\nSESSION_INITRD=%q\nSESSION_CRASHDUMP=%q\nSESSION_PANIC_ON_WARN=%q\nSESSION_NET_BUS=%q\nSESSION_NET_IP=%q\nSESSION_NET_MAC=%q\nSESSION_NET_IF=%q\nSESSION_NET_LINKS=%q\nSESSION_SSH_ENABLED=%q\nSESSION_SSH_AUTH=%q\nSESSION_SSH_HOST=%q\nSESSION_SSH_BIND=%q\nSESSION_SSH_PORT=%q\nSESSION_SSH_KEY=%q\n' \
    "$target" "$ARCH" "$profile" "$ACTIVE_USERSPACE_SPEC" "$kernel" "$proxy" "$sock" "$relay_pid" "$(qemu_control_mode_for_arch "$ARCH")" "$qmp" "$initrd" "$crashdump" "$panic_on_warn" "$net_bus" "$net_ip" "$net_mac" "$net_if" "$dir/network-links.tsv" "$([[ "$ssh_auth" != off ]] && echo 1 || echo 0)" "$ssh_auth" "127.0.0.1" "$ssh_bind" "$ssh_port" "$ssh_key" > "$dir/session.env"

  if ! session_rpc_boot_ready "$proxy" "$BOOT_TIMEOUT" >/dev/null 2>&1 && ! session_rpc_boot_ready "$proxy" "$BOOT_TIMEOUT" >/dev/null 2>&1; then
    if crash_log_has_panic "$console"; then
      capture_session_crash "$name" || true
      die "session '$name' panicked during boot; see $console"
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      die "session '$name' exited during boot; see $console and $dir/qemu-error.log"
    fi
    die "session '$name' control channel did not become ready within ${BOOT_TIMEOUT}s; see $console"
  fi
  # Very old e1000 drivers can block their first SIOCSIFFLAGS while QEMU's
  # emulated link is still settling immediately after init announces ready.
  # A short target-scoped pause avoids a multi-minute autonegotiation stall.
  if legacy_guest_busybox_target "$target" && { ((${#net_ids[@]} > 0)) || [[ "$ssh_auth" != off ]]; }; then
    sleep 2
  fi
  if ((${#net_ids[@]})); then
    : > "$dir/network.txt"
    for ((i=0;i<${#net_ids[@]};i++)); do configure_guest_network "$proxy" "${net_ips[$i]}" "${net_ifs[$i]}" "${net_macs[$i]}" >> "$dir/network.txt" || die "session '$name' failed to configure guest network ${net_ips[$i]} on ${net_ifs[$i]}"; done
  fi
  if [[ "$ssh_auth" != off ]]; then
    local ssh_preauth="" dropbear_flags=""
    configure_guest_network "$proxy" "10.0.2.15/24" eth0 "$ssh_mac" >> "$dir/ssh-network.txt" || die "session '$name' failed to configure its SSH interface"
    case "$ssh_auth" in
      key) ssh_preauth='sed -i "s|^root:[^:]*:|root:x:|" /etc/passwd; [ ! -e /etc/shadow ] || sed -i "s|^root:[^:]*:|root:x:|" /etc/shadow;'; dropbear_flags='-s -g' ;;
      password) ssh_preauth="sed -i 's|^root:[^:]*:|root:$ssh_shadow_hash:|' /etc/shadow;" ;;
      none) ssh_preauth='sed -i "s|^root:[^:]*:|root::|" /etc/shadow;'; dropbear_flags='-B' ;;
    esac
    if [[ "$target" == upstream:v2.0.40 || "$target" == upstream:v2.2.26 ]]; then
      # Linux 2.0/2.2 cannot seed their random pool from modern virtual
      # hardware. Repeatedly credit a fresh, host-generated seed before the
      # old Dropbear child performs key exchange and public-key validation.
      session_rpc_exec "$proxy" "i=0; while [ \$i -lt 16 ]; do /bin/klab-add-entropy /etc/klab-entropy || exit 72; i=\$(expr \$i + 1); done; mkdir -p /var/run/dropbear /root/.ssh; chown -R 0:0 /root; chmod 700 /root /root/.ssh; [ ! -f /root/.ssh/authorized_keys ] || chmod 600 /root/.ssh/authorized_keys" > "$dir/dropbear-prepare.txt" 2>&1 || die "session '$name' failed to prepare historical Dropbear; see $dir/dropbear-prepare.txt"
      # The sealed historical root already has a locked root password and the
      # requested authorized key. Avoid old sed implementations that lack -i.
      session_rpc_exec "$proxy" "/usr/sbin/dropbear -F -E $dropbear_flags -r /etc/dropbear/dropbear_rsa_host_key -p 22 >/tmp/klab-dropbear.log 2>&1 & p=\$!; sleep 1; kill -0 \$p 2>/dev/null || { cat /tmp/klab-dropbear.log; exit 71; }; cat /tmp/klab-dropbear.log 2>/dev/null || true" > "$dir/dropbear-start.txt" 2>&1 || die "session '$name' failed to start historical Dropbear; see $dir/dropbear-start.txt"
      printf '%s\n' dropbear-0.44 > "$dir/ssh-backend"
    elif [[ "$ACTIVE_USERSPACE_SPEC" == native:* ]]; then
      local openssh_flags native_ssh_backend
      native_ssh_backend="$(cat "$INITRAMFS/$key.session.root/etc/klab-ssh-backend" 2>/dev/null || echo openssh)"
      case "$ssh_auth" in
        key) openssh_flags='-o PasswordAuthentication=no -o PermitRootLogin=without-password' ;;
        password) openssh_flags='-o PasswordAuthentication=yes -o PermitRootLogin=yes' ;;
        none) openssh_flags='-o PasswordAuthentication=yes -o PermitEmptyPasswords=yes -o PermitRootLogin=yes' ;;
      esac
      if [[ "$native_ssh_backend" == openssh ]]; then
        session_rpc_exec "$proxy" "i=0; while [ \$(cat /sys/class/net/eth0/carrier 2>/dev/null) != 1 ] && [ \$i -lt 100 ]; do i=\$((i + 1)); sleep 0.1; done; command -v ethtool >/dev/null 2>&1 && ethtool -K eth0 tx off tso off gso off || true; mkdir -p /run/sshd /root/.ssh; chmod 700 /root/.ssh; [ ! -f /root/.ssh/authorized_keys ] || chmod 600 /root/.ssh/authorized_keys; [ -e /etc/shadow ] || pwconv; $ssh_preauth ssh-keygen -A; /usr/sbin/sshd -D -e -f /dev/null -o Port=22 -o ListenAddress=0.0.0.0 -o UsePAM=no $openssh_flags >/tmp/klab-openssh.log 2>&1 & sshd_pid=\$!; sleep 1; if ! kill -0 \$sshd_pid 2>/dev/null; then cat /tmp/klab-openssh.log >&2; exit 70; fi; cat /tmp/klab-openssh.log 2>/dev/null || true" > "$dir/openssh-start.txt" 2>&1 || die "session '$name' failed to start OpenSSH; see $dir/openssh-start.txt"
      else
        session_rpc_exec "$proxy" "i=0; while [ \$(cat /sys/class/net/eth0/carrier 2>/dev/null) != 1 ] && [ \$i -lt 100 ]; do i=\$((i + 1)); sleep 0.1; done; command -v ethtool >/dev/null 2>&1 && ethtool -K eth0 tx off tso off gso off || true; mkdir -p /var/run/dropbear /root/.ssh; chown -R 0:0 /root; chmod 700 /root /root/.ssh; [ ! -f /root/.ssh/authorized_keys ] || chmod 600 /root/.ssh/authorized_keys; [ -e /etc/shadow ] || pwconv; /usr/bin/dropbearkey -t ed25519 -f /var/run/dropbear/hostkey >/dev/null; $ssh_preauth /usr/sbin/dropbear -F -E $dropbear_flags -r /var/run/dropbear/hostkey -p 22 >/tmp/klab-dropbear.log 2>&1 & dropbear_pid=\$!; sleep 1; if ! kill -0 \$dropbear_pid 2>/dev/null; then cat /tmp/klab-dropbear.log >&2; exit 71; fi; cat /tmp/klab-dropbear.log 2>/dev/null || true" > "$dir/dropbear-start.txt" 2>&1 || die "session '$name' failed to start Dropbear; see $dir/dropbear-start.txt"
      fi
      printf '%s
' "$native_ssh_backend" > "$dir/ssh-backend"
    else
      # Old BusyBox read implementations truncate long serial RPC lines. Keep
      # setup, key generation, and daemon launch as independent short requests.
      session_rpc_exec "$proxy" "mkdir -p /var/run/dropbear /root/.ssh; chown -R 0:0 /root; chmod 700 /root /root/.ssh; [ ! -f /root/.ssh/authorized_keys ] || chmod 600 /root/.ssh/authorized_keys" > "$dir/dropbear-prepare.txt" 2>&1 || die "session '$name' failed to prepare Dropbear; see $dir/dropbear-prepare.txt"
      session_rpc_exec "$proxy" "$ssh_preauth /usr/bin/dropbearkey -t rsa -s 2048 -f /var/run/dropbear/hostkey >/dev/null" > "$dir/dropbear-keygen.txt" 2>&1 || die "session '$name' failed to generate a Dropbear host key; see $dir/dropbear-keygen.txt"
      session_rpc_exec "$proxy" "/usr/sbin/dropbear -F -E $dropbear_flags -r /var/run/dropbear/hostkey -p 22 >/tmp/klab-dropbear.log 2>&1 & p=\$!; sleep 1; kill -0 \$p 2>/dev/null || { cat /tmp/klab-dropbear.log; exit 71; }; cat /tmp/klab-dropbear.log 2>/dev/null || true" > "$dir/dropbear-start.txt" 2>&1 || die "session '$name' failed to start Dropbear; see $dir/dropbear-start.txt"
    fi
  fi
  nohup bash "$SELF_PATH" _crash-watch "$name" >"$dir/crash-watcher.log" 2>&1 &
  printf '%s\n' "$!" > "$dir/crash-watcher.pid"
  say "Session '$name' is ready"
  [[ "$crashdump" == 1 ]] && say "Optional vmcore capture is armed for kernel panic"
  [[ "$panic_on_warn" == 1 ]] && say "Strict mode: kernel WARN() is configured to panic"
  [[ "$ssh_auth" != off ]] && say "SSH ready ($ssh_auth, bind $ssh_bind): $SELF_PATH ssh $name"
  printf '%s\n' "$name"
}


capture_session_crash() {
  local name="$1" dir pid target profile kernel qmp crashdump crash_tmp='' out
  dir="$(session_dir "$name")"
  [[ -f "$dir/session.env" ]] || return 1
  unset SESSION_TARGET SESSION_PROFILE SESSION_KERNEL SESSION_QMP SESSION_CRASHDUMP
  # shellcheck disable=SC1090
  source "$dir/session.env"
  target="${SESSION_TARGET:-unknown}"; profile="${SESSION_PROFILE:-normal}"; kernel="${SESSION_KERNEL:-}"
  qmp="${SESSION_QMP:-}"; crashdump="${SESSION_CRASHDUMP:-0}"
  [[ -f "$dir/console.log" ]] || return 1
  crash_log_has_panic "$dir/console.log" || return 1
  [[ -f "$dir/crash-captured" ]] && return 0
  : > "$dir/crash-captured"
  if [[ "$crashdump" == 1 && -n "$qmp" && -S "$qmp" ]]; then
    crash_tmp="$CRASHES/.session-${name}-$(date +%s).vmcore.tmp"
    say "Session '$name': capturing QEMU vmcore ($CRASHDUMP_FORMAT)"
    if ! qmp_dump_guest_memory "$qmp" "$crash_tmp" "$CRASHDUMP_FORMAT"; then
      say "Warning: session '$name' vmcore capture failed"
      rm -f "$crash_tmp"; crash_tmp=''
    fi
  fi
  out="$(archive_crash_artifacts "session-${name}" "$target" "$profile" "$dir/console.log" "$kernel" "$crash_tmp" "$dir")"
  printf '%s\n' "$out" > "$dir/crash-path"
  say "Session '$name' crash artifacts: $out"
}

cmd_internal_crash_watch() {
  (($# == 1)) || exit 2
  local name="$1" dir pid
  dir="$(session_dir "$name")"
  [[ -f "$dir/pid" ]] || exit 0
  pid="$(cat "$dir/pid")"
  while kill -0 "$pid" 2>/dev/null; do
    if crash_log_has_panic "$dir/console.log"; then
      capture_session_crash "$name" || true
      exit 0
    fi
    sleep 0.25
  done
  crash_log_has_panic "$dir/console.log" && capture_session_crash "$name" || true
}

cmd_crashes() {
  printf '%-36s %-56s %-9s %s\n' CRASH TARGET PROFILE VMCORE
  printf '%-36s %-56s %-9s %s\n' '-----' '------' '-------' '------'
  local d target='?' profile='?' vm='no'
  [[ -d "$CRASHES" ]] || return 0
  for d in "$CRASHES"/*; do
    [[ -d "$d" && -f "$d/crash.env" ]] || continue
    unset TARGET PROFILE VMCORE
    # shellcheck disable=SC1090
    source "$d/crash.env"
    [[ -n "${VMCORE:-}" && -f "${VMCORE:-}" ]] && vm=yes || vm=no
    printf '%-36s %-56s %-9s %s\n' "$(basename "$d")" "${TARGET:-?}" "${PROFILE:-?}" "$vm"
  done
}

cmd_crash_info() {
  (($# == 1)) || die "usage: $0 crash-info <CRASH-ID|SESSION>"
  local q="$1" d="" sdir
  if [[ -d "$CRASHES/$q" ]]; then d="$CRASHES/$q"; fi
  if [[ -z "$d" ]]; then
    sdir="$(session_dir "$q")"
    [[ -f "$sdir/crash-path" ]] && d="$(cat "$sdir/crash-path")"
  fi
  [[ -n "$d" && -f "$d/crash.env" ]] || die "no captured crash found for '$q'"
  unset CRASH_ID TARGET PROFILE KERNEL_IMAGE VMLINUX VMCORE CAPTURED_AT
  # shellcheck disable=SC1090
  source "$d/crash.env"
  printf 'Crash:       %s\nTarget:      %s\nProfile:     %s\nCaptured:    %s\nConsole:     %s\n' \
    "${CRASH_ID:-$(basename "$d")}" "${TARGET:-?}" "${PROFILE:-?}" "${CAPTURED_AT:-?}" "$d/console.log"
  [[ -n "${VMCORE:-}" && -f "${VMCORE:-}" ]] && printf 'VM core:     %s\n' "$VMCORE" || printf 'VM core:     not captured\n'
  [[ -n "${VMLINUX:-}" && -f "${VMLINUX:-}" ]] && printf 'vmlinux:     %s\n' "$VMLINUX" || true
  [[ -f "$d/loaded-modules.tsv" ]] && printf 'Modules:     %s\n' "$d/loaded-modules.tsv"
  printf '\nLast console lines:\n'
  tail -n 80 "$d/console-tail.log" 2>/dev/null || true
}

cmd_sessions() {
  printf '%-20s %-9s %-8s %-9s %-20s %-42s %s\n' SESSION STATE BACKEND ARCH USERSPACE TARGET PROFILE
  printf '%-20s %-9s %-8s %-9s %-20s %-42s %s\n' '-------' '-----' '-------' '----' '---------' '------' '-------'
  local dir name state target='?' profile='?' backend='?' arch='?' userspace='?' pid
  [[ -d "$SESSIONS" ]] || return 0
  for dir in "$SESSIONS"/*; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"; state=stopped; target='?'; profile='?'; arch='?'; userspace='?'
    if [[ -f "$dir/session.env" ]]; then
      unset SESSION_TARGET SESSION_BACKEND SESSION_ARCH SESSION_PROFILE SESSION_USERSPACE
      # shellcheck disable=SC1090
      source "$dir/session.env"
      target="${SESSION_TARGET:-?}"; backend="${SESSION_BACKEND:-linux}"; arch="${SESSION_ARCH:-x86_64}"; profile="${SESSION_PROFILE:-?}"; userspace="${SESSION_USERSPACE:-?}"
    fi
    if [[ -f "$dir/pid" ]]; then pid="$(cat "$dir/pid")"; kill -0 "$pid" 2>/dev/null && state=running; fi
    if [[ -f "$dir/crash-captured" ]] || crash_log_has_panic "$dir/console.log"; then state=crashed; fi
    printf '%-20s %-9s %-8s %-9s %-20s %-42s %s\n' "$name" "$state" "$backend" "$arch" "$userspace" "$target" "$profile"
  done
}

load_session_env() {
  local name="$1" dir
  session_require_running "$name"
  dir="$(session_dir "$name")"
  [[ -f "$dir/session.env" ]] || die "session '$name' metadata is missing"
  unset SESSION_TARGET SESSION_BACKEND SESSION_ARCH SESSION_PROFILE SESSION_KERNEL SESSION_CONTROL SESSION_QMP SESSION_INITRD SESSION_CRASHDUMP SESSION_PANIC_ON_WARN SESSION_NET_BUS SESSION_NET_IP SESSION_NET_MAC SESSION_NET_IF SESSION_NET_LINKS
  # shellcheck disable=SC1090
  source "$dir/session.env"
  [[ -n "${SESSION_ARCH:-}" ]] && ARCH="$(canonical_arch "$SESSION_ARCH")"
}

cmd_ssh_session() {
  (($# >= 1)) || die "usage: $0 ssh <SESSION> [-- SSH_OPTIONS...]"
  local name="$1"; shift
  [[ "${1:-}" != -- ]] || shift
  load_session_env "$name"
  [[ "${SESSION_BACKEND:-linux}" == linux ]] || die "SSH sessions currently support Linux guests only"
  [[ "${SESSION_SSH_ENABLED:-0}" == 1 ]] || die "session '$name' was not started with SSH enabled"
  have ssh || die "the host ssh client is required"
  local -a auth_args=() compatibility_args=()
  case "${SESSION_SSH_AUTH:-key}" in
    key) [[ -f "${SESSION_SSH_KEY:-}" ]] || die "SSH private key is unavailable: ${SESSION_SSH_KEY:-unset}"; auth_args=(-o IdentitiesOnly=yes -i "$SESSION_SSH_KEY") ;;
    password|none) auth_args=(-o PreferredAuthentications=password -o PubkeyAuthentication=no) ;;
    *) die "session '$name' has invalid SSH authentication metadata" ;;
  esac
  case "${SESSION_TARGET:-}" in
    upstream:v2.0.40|upstream:v2.2.26)
      # Dropbear 0.44 has a small KEXINIT buffer. Exact proposals avoid the
      # much larger modern OpenSSH defaults and match its historical suite.
      compatibility_args=(-o HostkeyAlgorithms=ssh-rsa -o PubkeyAcceptedAlgorithms=ssh-rsa -o KexAlgorithms=diffie-hellman-group1-sha1 -o Ciphers=aes128-cbc -o MACs=hmac-sha1 -o Compression=no)
      ;;
  esac
  exec ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$(session_dir "$name")/ssh-known-hosts" "${auth_args[@]}" "${compatibility_args[@]}" -p "$SESSION_SSH_PORT" "$@" "root@$SESSION_SSH_HOST"
}

cmd_push_session() {
  (($# == 2 || $# == 3)) || die "usage: $0 push <SESSION> <LOCAL> [REMOTE]"
  local name="$1" local_file="$2" remote="${3:-}" mode=0644 size flow=ack attempt rc=1
  [[ -f "$local_file" ]] || die "file not found: $local_file"
  [[ -n "$remote" ]] || remote="/tmp/klab-files/$(basename "$local_file")"
  [[ -x "$local_file" ]] && mode=0755
  load_session_env "$name"
  say "Uploading $local_file -> $name:$remote"
  if [[ "${SESSION_BACKEND:-linux}" == freebsd ]]; then
    size="$(session_rpc_put_exec "$SESSION_CONTROL" "$local_file" "$remote" "$mode")" || die "FreeBSD upload failed: $local_file -> $name:$remote"
    printf '%s\t%s\n' "$remote" "$size"
    return 0
  fi
  [[ "${SESSION_CONTROL_MODE:-}" == serial ]] && flow=serial
  for attempt in 1 2 3; do
    if size="$(session_rpc_put "$SESSION_CONTROL" "$local_file" "$remote" "$mode" "$flow")"; then
      printf '%s\t%s\n' "$remote" "$size"
      return 0
    fi
    rc=$?
    (( attempt < 3 )) && say "Upload acknowledgement failed; retrying whole file ($attempt/3)"
  done
  die "upload failed after 3 attempts: $local_file -> $name:$remote (last rc=$rc)"
}

cmd_exec_session() {
  (($# >= 2)) || die "usage: $0 exec <SESSION> <COMMAND>"
  local name="$1"; shift
  local command="$*"
  load_session_env "$name"
  session_rpc_exec "$SESSION_CONTROL" "$command"
}

cmd_link_session() {
  (($# == 3)) || die "usage: $0 link <SESSION> <DEVICE-ID> <up|down>"
  local name="$1" device="$2" state="$3" up
  [[ "$device" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid QEMU network device id '$device'"
  case "$state" in up) up=true ;; down) up=false ;; *) die "link state must be 'up' or 'down'" ;; esac
  load_session_env "$name"
  [[ "${SESSION_BACKEND:-linux}" == linux ]] || die "link control currently requires a QEMU Linux session"
  [[ -n "${SESSION_QMP:-}" ]] || die "session '$name' has no QMP control socket"
  qmp_set_link "$SESSION_QMP" "$device" "$up" >/dev/null
  printf '%s\t%s\n' "$device" "$state"
}

posix_shell_join() {
  python3 - "$@" <<'PYJOIN'
import shlex,sys
print(shlex.join(sys.argv[1:]))
PYJOIN
}

cmd_insmod_session() {
  (($# >= 2)) || die "usage: $0 insmod <SESSION> <MODULE.ko> [module-args...]"
  local name="$1"
  load_session_env "$name"
  [[ "${SESSION_BACKEND:-linux}" == linux ]] || die "'insmod' is the Linux compatibility alias; use '$0 load-module $*' for backend-neutral operation"
  cmd_load_module_session "$@"
}

cmd_stop_session() {
  (($# == 1)) || die "usage: $0 stop <SESSION>"
  local name="$1" dir pid sock i
  dir="$(session_dir "$name")"
  [[ -f "$dir/session.env" && -f "$dir/pid" ]] || die "unknown session '$name'"
  unset SESSION_TARGET SESSION_BACKEND SESSION_PROFILE SESSION_KERNEL SESSION_CONTROL SESSION_CONTROL_UPSTREAM SESSION_CONTROL_RELAY_PID SESSION_QMP SESSION_INITRD SESSION_CRASHDUMP SESSION_PANIC_ON_WARN
  # shellcheck disable=SC1090
  source "$dir/session.env"
  pid="$(cat "$dir/pid")"; sock="${SESSION_CONTROL:-}"
  if crash_log_has_panic "$dir/console.log"; then
    capture_session_crash "$name" || true
  elif kill -0 "$pid" 2>/dev/null && [[ -n "$sock" && -S "$sock" ]]; then
    session_rpc_exec "$sock" 'sync; poweroff -f 2>/dev/null || reboot -f 2>/dev/null || true' 1 >/dev/null 2>&1 || true
  fi
  for i in {1..30}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null || true; fi
  for i in {1..30}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then kill -KILL "$pid" 2>/dev/null || true; fi
  if [[ -n "${SESSION_CONTROL_RELAY_PID:-}" ]]; then kill "$SESSION_CONTROL_RELAY_PID" 2>/dev/null || true; fi
  rm -f "$sock" "${SESSION_CONTROL_UPSTREAM:-}" "${SESSION_QMP:-}"
  if [[ -f "$dir/crash-watcher.pid" ]]; then kill "$(cat "$dir/crash-watcher.pid")" 2>/dev/null || true; fi
  say "Session '$name' stopped; console log retained at $dir/console.log"
}

cmd_test_stable() {
  (($# >= 1)) || die "usage: $0 test <target> --module DIR --script FILE [--arch ARCH] [--profile PROFILE] [--userspace SPEC] [--crashdump] [--panic-on-warn]"
  local requested="$1" target; shift
  local module_dir="" test_script="" profile=normal crashdump=0 panic_on_warn=0 arch="$ARCH" userspace="${KLAB_USERSPACE:-auto}"
  while (($#)); do
    case "$1" in
      --module|-m) [[ $# -ge 2 ]] || die "$1 needs a directory"; module_dir="$2"; shift 2 ;;
      --script|-s) [[ $# -ge 2 ]] || die "$1 needs a file"; test_script="$2"; shift 2 ;;
      --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; arch="$(canonical_arch "$2")"; shift 2 ;;
      --profile|-p) [[ $# -ge 2 ]] || die "$1 needs a profile"; profile="$2"; shift 2 ;;
      --userspace) [[ $# -ge 2 ]] || die "--userspace needs a value"; userspace="$2"; shift 2 ;;
      --crashdump) crashdump=1; shift ;;
      --panic-on-warn) panic_on_warn=1; shift ;;
      *) die "unknown test option '$1'" ;;
    esac
  done
  [[ -n "$module_dir" ]] || die "test requires --module DIR"; [[ -n "$test_script" ]] || die "test requires --script FILE"
  set_active_arch "$arch"; target="$(effective_target_for_arch "$requested" "$ARCH")"
  resolve_active_userspace "$target" "$profile" "$userspace"
  run_stable_target_test "$target" "$profile" "$module_dir" "$test_script" "$crashdump" "$panic_on_warn"
}

cmd_smoke() {
  (($# >= 1)) || die "usage: $0 smoke <target> [--arch ARCH] [--profile PROFILE] [--userspace SPEC] [--crashdump] [--panic-on-warn]"
  local requested="$1" target profile=normal crashdump=0 panic_on_warn=0 arch="$ARCH" userspace="${KLAB_USERSPACE:-auto}"; shift
  while (($#)); do
    case "$1" in
      --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; arch="$(canonical_arch "$2")"; shift 2 ;;
      --profile|-p) [[ $# -ge 2 ]] || die "$1 needs a profile"; profile="$2"; shift 2 ;;
      --userspace) [[ $# -ge 2 ]] || die "--userspace needs a value"; userspace="$2"; shift 2 ;;
      --crashdump) crashdump=1; shift ;;
      --panic-on-warn) panic_on_warn=1; shift ;;
      *) die "unknown smoke option '$1'" ;;
    esac
  done
  set_active_arch "$arch"; target="$(effective_target_for_arch "$requested" "$ARCH")"
  resolve_active_userspace "$target" "$profile" "$userspace"
  if [[ "$(target_backend "$target")" == freebsd ]]; then
    ensure_freebsd_examples; run_stable_target_test "$target" normal "$EXAMPLES/freebsd-hello" "$EXAMPLES/freebsd-test.sh" "$crashdump" "$panic_on_warn"
  else
    [[ -f "$EXAMPLES/hello/Makefile" && -f "$EXAMPLES/test.sh" ]] || die "built-in Linux smoke test missing; run '$0 init'"
    run_stable_target_test "$target" "$profile" "$EXAMPLES/hello" "$EXAMPLES/test.sh" "$crashdump" "$panic_on_warn"
  fi
}

cmd_test_set() {
  local module_dir="" test_script="" profile=normal crashdump=0 panic_on_warn=0 arch="$ARCH" userspace="${KLAB_USERSPACE:-auto}"
  local workers="${KLAB_WORKERS:-1}" jobs_per_worker=""
  local -a targets=()
  while (($#)); do
    case "$1" in
      --module|-m) [[ $# -ge 2 ]] || die "$1 needs a directory"; module_dir="$2"; shift 2 ;;
      --script|-s) [[ $# -ge 2 ]] || die "$1 needs a file"; test_script="$2"; shift 2 ;;
      --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; arch="$(canonical_arch "$2")"; shift 2 ;;
      --profile|-p) [[ $# -ge 2 ]] || die "$1 needs a profile"; profile="$2"; shift 2 ;;
      --userspace) [[ $# -ge 2 ]] || die "--userspace needs a value"; userspace="$2"; shift 2 ;;
      --workers|-w) [[ $# -ge 2 ]] || die "$1 needs a number"; workers="$2"; shift 2 ;;
      --jobs-per-worker) [[ $# -ge 2 ]] || die "$1 needs a number"; jobs_per_worker="$2"; shift 2 ;;
      --crashdump) crashdump=1; shift ;;
      --panic-on-warn) panic_on_warn=1; shift ;;
      --) shift; targets+=("$@"); break ;;
      -*) die "unknown test-set option '$1'" ;;
      *) targets+=("$1"); shift ;;
    esac
  done
  [[ -n "$module_dir" ]] || die "test-set requires --module DIR"
  [[ -n "$test_script" ]] || die "test-set requires --script FILE"
  ((${#targets[@]} > 0)) || die "test-set needs at least one target"
  [[ "$workers" =~ ^[1-9][0-9]*$ ]] || die "--workers must be a positive integer"
  if [[ -z "$jobs_per_worker" ]]; then
    jobs_per_worker=$(( JOBS / workers )); (( jobs_per_worker < 1 )) && jobs_per_worker=1
  fi
  [[ "$jobs_per_worker" =~ ^[1-9][0-9]*$ ]] || die "--jobs-per-worker must be a positive integer"
  set_active_arch "$arch"

  # Preserve streaming output for the common single-worker case.
  if (( workers == 1 )); then
    local total=${#targets[@]} failures=0 requested target
    for requested in "${targets[@]}"; do
      target="$(effective_target_for_arch "$requested" "$ARCH")"
      resolve_active_userspace "$target" "$profile" "$userspace"
      printf '\n################################################################\n### %s [%s] / userspace=%s\n################################################################\n' "$requested" "$ARCH" "$ACTIVE_USERSPACE_SPEC"
      local old_jobs="$JOBS"; JOBS="$jobs_per_worker"
      if ! run_stable_target_test "$target" "$profile" "$module_dir" "$test_script" "$crashdump" "$panic_on_warn"; then failures=$((failures + 1)); fi
      JOBS="$old_jobs"
    done
    printf '\nTest set complete: %d passed, %d failed, %d total.\n' "$((total-failures))" "$failures" "$total"
    (( failures == 0 )); return
  fi

  local runid runroot active=0 idx=0 requested safe log result
  runid="$(date +%Y%m%d-%H%M%S)-$$"; runroot="$LOGS/test-set-$runid"; mkdir -p "$runroot"
  say "Running ${#targets[@]} tests with $workers workers and make -j$jobs_per_worker per worker"
  for requested in "${targets[@]}"; do
    idx=$((idx+1)); safe="$(printf '%s' "$requested" | tr ':@/' '___')"; log="$runroot/$(printf '%03d' "$idx")-$safe.log"; result="$log.result"
    (
      set +e
      (
        export KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" KLAB_OFFLINE="$OFFLINE" KLAB_ARCH="$ARCH" KLAB_USERSPACE="$userspace" KLAB_JOBS="$jobs_per_worker"
        args=(test "$requested" --arch "$ARCH" --profile "$profile" --userspace "$userspace" --module "$module_dir" --script "$test_script")
        [[ "$crashdump" == 1 ]] && args+=(--crashdump)
        [[ "$panic_on_warn" == 1 ]] && args+=(--panic-on-warn)
        bash "$SELF_PATH" "${args[@]}"
      ) >"$log" 2>&1
      rc=$?; printf '%s\n' "$rc" > "$result"; exit 0
    ) &
    active=$((active+1))
    if (( active >= workers )); then wait -n || true; active=$((active-1)); fi
  done
  wait || true

  local total=${#targets[@]} failures=0 rc
  idx=0
  printf '\n%-6s %-52s %s\n' RESULT TARGET LOG
  printf '%-6s %-52s %s\n' '------' '------' '---'
  for requested in "${targets[@]}"; do
    idx=$((idx+1)); safe="$(printf '%s' "$requested" | tr ':@/' '___')"; log="$runroot/$(printf '%03d' "$idx")-$safe.log"; result="$log.result"
    rc="$(cat "$result" 2>/dev/null || echo 99)"
    if [[ "$rc" == 0 ]]; then printf '%-6s %-52s %s\n' PASS "$requested" "$log"; else printf '%-6s %-52s %s\n' FAIL "$requested" "$log"; failures=$((failures+1)); fi
  done
  printf '\nTest set complete: %d passed, %d failed, %d total. Logs: %s\n' "$((total-failures))" "$failures" "$total" "$runroot"
  (( failures == 0 ))
}

cmd_matrix_targets() {
  local module_dir="$1" test_script="$2"; shift 2
  (($# > 0)) || die "matrix-targets needs at least one target"
  local total=$# failures=0 target provider
  for target in "$@"; do
    printf '\n################################################################\n'
    printf '### %s\n' "$target"
    printf '################################################################\n'
    provider="${target%%:*}"
    if [[ "$provider" == upstream ]]; then
      if ! cmd_test_legacy "${target#upstream:}" normal "$module_dir" "$test_script"; then failures=$((failures + 1)); fi
    else
      if ! cmd_distro_test "$target" "$module_dir" "$test_script"; then failures=$((failures + 1)); fi
    fi
  done
  printf '\nTarget matrix complete: %d failure(s) out of %d target(s).\n' "$failures" "$total"
  (( failures == 0 ))
}


# ---------------------------------------------------------------------------
# Generic custom Linux targets and reusable cross-compilation interface
# ---------------------------------------------------------------------------

cmd_register_linux() {
  (($# >= 1)) || die "usage: $0 register-linux <NAME> --release RELEASE --kernel IMAGE --build-dir DIR [--source-dir DIR] [--modules-dir DIR] [--arch ARCH] [--copy|--reference]"
  local name="$1" release="" kernel="" build="" source="" modules="" arch="$ARCH" mode=copy dest target
  shift
  validate_token "$name" custom-target-name
  while (($#)); do
    case "$1" in
      --release) [[ $# -ge 2 ]] || die "--release needs a value"; release="$2"; shift 2 ;;
      --kernel) [[ $# -ge 2 ]] || die "--kernel needs a file"; kernel="$2"; shift 2 ;;
      --build-dir) [[ $# -ge 2 ]] || die "--build-dir needs a directory"; build="$2"; shift 2 ;;
      --source-dir) [[ $# -ge 2 ]] || die "--source-dir needs a directory"; source="$2"; shift 2 ;;
      --modules-dir) [[ $# -ge 2 ]] || die "--modules-dir needs a directory"; modules="$2"; shift 2 ;;
      --arch) [[ $# -ge 2 ]] || die "--arch needs a value"; arch="$(canonical_arch "$2")"; shift 2 ;;
      --copy) mode=copy; shift ;;
      --reference) mode=reference; shift ;;
      *) die "unknown register-linux option '$1'" ;;
    esac
  done
  [[ -n "$release" ]] || die "register-linux requires --release"
  validate_token "$release" kernel-release
  [[ -f "$kernel" ]] || die "kernel image not found: $kernel"
  [[ -d "$build" ]] || die "kernel build directory not found: $build"
  [[ -z "$source" || -d "$source" ]] || die "kernel source directory not found: $source"
  [[ -z "$modules" || -d "$modules" ]] || die "kernel modules directory not found: $modules"
  set_active_arch "$arch"
  target="custom:$name:$release"
  dest="$(bundle_dir_for custom "$name" "$release" "$ARCH")"
  rm -rf "$dest"; mkdir -p "$dest"

  local kdst bdst sdst mdst
  if [[ "$mode" == copy ]]; then
    say "Registering portable custom Linux target $target [$ARCH]"
    kdst="$dest/vmlinuz"; cp -a "$kernel" "$kdst"
    bdst="$dest/build"; cp -a "$build" "$bdst"
    if [[ -n "$source" ]]; then sdst="$dest/source"; cp -a "$source" "$sdst"; else sdst=""; fi
    if [[ -n "$modules" ]]; then mdst="$dest/modules"; cp -a "$modules" "$mdst"; else mdst=""; fi
  else
    say "Registering local-reference custom Linux target $target [$ARCH]"
    kdst="$(readlink -f "$kernel")"; bdst="$(readlink -f "$build")"
    [[ -n "$source" ]] && sdst="$(readlink -f "$source")" || sdst=""
    [[ -n "$modules" ]] && mdst="$(readlink -f "$modules")" || mdst=""
  fi

  cat > "$dest/bundle.env" <<EOF_CUSTOM
BUNDLE_PROVIDER=custom
BUNDLE_DISTRO_RELEASE=$(printf '%q' "$name")
BUNDLE_KERNEL_RELEASE=$(printf '%q' "$release")
BUNDLE_TARGET_ID=$(printf '%q' "$target")
BUNDLE_BACKEND=linux
BUNDLE_ARCH=$(printf '%q' "$ARCH")
BUNDLE_KERNEL_IMAGE=$(printf '%q' "$kdst")
BUNDLE_BUILD_DIR=$(printf '%q' "$bdst")
BUNDLE_SOURCE_DIR=$(printf '%q' "$sdst")
BUNDLE_MODULES_DIR=$(printf '%q' "$mdst")
BUNDLE_PACKAGES=
BUNDLE_ROOT=
BUNDLE_BUILD_IMAGE=
BUNDLE_FETCHED_AT=$(printf '%q' "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
BUNDLE_CAPABILITIES=boot,push,exec,module-build,module-load,module-unload,module-list,crash-console,crash-vmcore
BUNDLE_TOOLCHAIN_BOUND=0
BUNDLE_CUSTOM_MODE=$(printf '%q' "$mode")
EOF_CUSTOM
  say "Registered $target [$ARCH]"
  if [[ "$mode" == reference ]]; then
    say "Reference mode is local-only. Use --copy before exporting a portable .klab bundle."
  fi
  printf '%s\n' "$target"
}

cross_sdk_for_arch() {
  local arch="$(canonical_arch "$1")" profile="$2"
  case "$profile" in minimal|network) ;; *) die "cross profile must be minimal or network" ;; esac
  ensure_buildroot_sdk "$arch" "$profile"
}

cross_env_values() {
  local arch="$1" profile="$2" sdk cc prefix sysroot cxx ar ld strip
  sdk="$(cross_sdk_for_arch "$arch" "$profile")"
  cc="$(sdk_compiler "$sdk")"
  prefix="${cc%gcc}"
  cxx="${prefix}g++"; [[ -x "$cxx" ]] || cxx="${prefix}c++"
  ar="${prefix}ar"; ld="${prefix}ld"; strip="${prefix}strip"
  sysroot="$($cc --print-sysroot 2>/dev/null || true)"
  printf 'KLAB_CROSS_ARCH=%q\n' "$arch"
  printf 'KLAB_CROSS_PROFILE=%q\n' "$profile"
  printf 'KLAB_SDK=%q\n' "$sdk"
  printf 'PATH=%q\n' "$sdk/bin:$PATH"
  printf 'CC=%q\n' "$cc"
  [[ -x "$cxx" ]] && printf 'CXX=%q\n' "$cxx"
  [[ -x "$ar" ]] && printf 'AR=%q\n' "$ar"
  [[ -x "$ld" ]] && printf 'LD=%q\n' "$ld"
  [[ -x "$strip" ]] && printf 'STRIP=%q\n' "$strip"
  [[ -n "$sysroot" ]] && { printf 'SYSROOT=%q\n' "$sysroot"; printf 'PKG_CONFIG_SYSROOT_DIR=%q\n' "$sysroot"; }
}

cmd_cross() {
  local sub="${1:-}"; [[ -n "$sub" ]] || die "usage: $0 cross <env|exec|cc> ..."; shift
  local arch="$ARCH" profile=minimal output="" static=0
  local -a sources=() command=() extra=()
  case "$sub" in
    env)
      while (($#)); do
        case "$1" in --arch) arch="$(canonical_arch "$2")"; shift 2 ;; --profile) profile="$2"; shift 2 ;; *) die "unknown cross env option '$1'" ;; esac
      done
      cross_env_values "$arch" "$profile" | sed 's/^/export /'
      ;;
    exec)
      while (($#)); do
        case "$1" in
          --arch) arch="$(canonical_arch "$2")"; shift 2 ;;
          --profile) profile="$2"; shift 2 ;;
          --) shift; command=("$@"); break ;;
          *) command=("$@"); break ;;
        esac
      done
      ((${#command[@]})) || die "cross exec requires a command after --"
      local envfile; envfile="$(mktemp)"; cross_env_values "$arch" "$profile" > "$envfile"
      set -a; # shellcheck disable=SC1090
      source "$envfile"; set +a; rm -f "$envfile"
      exec "${command[@]}"
      ;;
    cc)
      while (($#)); do
        case "$1" in
          --arch) arch="$(canonical_arch "$2")"; shift 2 ;;
          --profile) profile="$2"; shift 2 ;;
          --source|-s) [[ $# -ge 2 ]] || die "$1 needs a file"; sources+=("$2"); shift 2 ;;
          -o|--output) [[ $# -ge 2 ]] || die "$1 needs a file"; output="$2"; shift 2 ;;
          --static) static=1; shift ;;
          --) shift; extra=("$@"); break ;;
          *) die "unknown cross cc option '$1' (compiler flags go after --)" ;;
        esac
      done
      ((${#sources[@]})) || die "cross cc requires at least one --source"
      local sdk cc; sdk="$(cross_sdk_for_arch "$arch" "$profile")"; cc="$(sdk_compiler "$sdk")"
      [[ -n "$output" ]] || output="./$(basename "${sources[0]%.*}")-$arch"
      local src; for src in "${sources[@]}"; do [[ -f "$src" ]] || die "source file not found: $src"; done
      mkdir -p "$(dirname "$output")"
      local args=("$cc"); (( static == 1 )) && args+=(-static); args+=("${sources[@]}" -o "$output" "${extra[@]}")
      "${args[@]}" || die "cross compilation failed"
      printf '%s\n' "$output"
      ;;
    *) die "usage: $0 cross <env|exec|cc>" ;;
  esac
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    init) shift; init_lab "$@" ;;
    mode) shift; cmd_mode "$@" ;;
    status) shift; (($# == 0)) || die "usage: $0 status"; cmd_status ;;
    doctor) shift; (($# == 0)) || die "usage: $0 doctor"; cmd_doctor ;;
    architectures) shift; (($# == 0)) || die "usage: $0 architectures"; cmd_architectures ;;
    arch-plan) shift; cmd_arch_plan "$@" ;;
    userspaces) shift; (($# == 0)) || die "usage: $0 userspaces"; cmd_userspaces ;;
    buildroot-cache) shift; cmd_buildroot_cache "$@" ;;
    register-linux) shift; cmd_register_linux "$@" ;;
    cross) shift; cmd_cross "$@" ;;
    prepare) shift; cmd_prepare "$@" ;;
    import) shift; cmd_import_bundle "$@" ;;
    verify) shift; cmd_verify_bundle "$@" ;;
    inspect) shift; cmd_inspect_bundle "$@" ;;

    # Advanced/backward-compatible commands.
    build) shift; (($# >= 1 && $# <= 2)) || { usage; exit 2; }; cmd_build "$@" ;;
    module) shift; (($# == 2 || $# == 3)) || { usage; exit 2; }; cmd_module "$@" ;;
    test) shift; cmd_test_stable "$@" ;;
    build-module) shift; cmd_build_module_stable "$@" ;;
    build-user) shift; cmd_build_user "$@" ;;
    arch-smoke) shift; cmd_arch_smoke "$@" ;;
    scenario-run) shift; cmd_scenario_run "$@" ;;
    multiguest-run) shift; cmd_multiguest_run "$@" ;;
    boot) shift; cmd_boot_session "$@" ;;
    sessions) shift; (($# == 0)) || die "usage: $0 sessions"; cmd_sessions ;;
    push) shift; cmd_push_session "$@" ;;
    exec) shift; cmd_exec_session "$@" ;;
    ssh) shift; cmd_ssh_session "$@" ;;
    link) shift; cmd_link_session "$@" ;;
    load-module) shift; cmd_load_module_session "$@" ;;
    unload-module) shift; cmd_unload_module_session "$@" ;;
    list-modules) shift; cmd_list_modules_session "$@" ;;
    insmod) shift; cmd_insmod_session "$@" ;;
    stop) shift; cmd_stop_session "$@" ;;
    crashes) shift; (($# == 0)) || die "usage: $0 crashes"; cmd_crashes ;;
    crash-info) shift; cmd_crash_info "$@" ;;
    _crash-watch) shift; cmd_internal_crash_watch "$@" ;;
    smoke) shift; cmd_smoke "$@" ;;
    test-set) shift; cmd_test_set "$@" ;;
    targets) shift; (($# == 0)) || die "usage: $0 targets"; cmd_targets ;;
    test-legacy) shift; (($# == 3 || $# == 4)) || { usage; exit 2; }; cmd_test_legacy "$@" ;;
    matrix) shift; (($# >= 4)) || { usage; exit 2; }; cmd_matrix "$@" ;;
    matrix-targets) shift; (($# >= 3)) || { usage; exit 2; }; cmd_matrix_targets "$@" ;;
    providers) shift; providers_show ;;
    capabilities) shift; cmd_capabilities "$@" ;;
    list)
      shift
      if (($# == 0)); then cmd_cache; else (($# <= 2)) || { usage; exit 2; }; cmd_provider_list "$@"; fi
      ;;
    fetch) shift; (($# == 1)) || { usage; exit 2; }; cmd_fetch "$1" ;;
    info) shift; cmd_info_stable "$@" ;;
    buildenv) shift; "$BUILDENV_BIN" "$@" ;;
    toolchain) shift; cmd_toolchain "$@" ;;
    cache) shift; cmd_cache "$@" ;;
    clean) shift; (($# >= 1 && $# <= 2)) || { usage; exit 2; }; cmd_clean "$@" ;;
    -h|--help|help|'') usage ;;
    *) usage; die "unknown command '$cmd'" ;;
  esac
}
main "$@"
