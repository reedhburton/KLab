#!/usr/bin/env bash
# KLab architecture/target model v1.
#
# Separates the architecture a kernel/program targets from the architecture of
# the worker/toolchain that builds it and the guest that executes it.
# Architecture profiles remain trusted local configuration.

KLAB_ARCH_MODEL_VERSION=1

klab_arch_profiles_dir(){
  if [[ -n "${KLAB_ARCH_PROFILES_DIR:-}" ]]; then printf '%s\n' "$KLAB_ARCH_PROFILES_DIR"
  elif [[ -n "${SELF_DIR:-}" && -d "${SELF_DIR}/architectures" ]]; then printf '%s\n' "${SELF_DIR}/architectures"
  else printf '%s\n' "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/architectures"
  fi
}
klab_arch_profile_files(){ local d; d="$(klab_arch_profiles_dir)"; [[ -d "$d" ]] || return 0; find "$d" -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null | sort; }
klab_arch_profile_field(){
  local arch="$1" field="$2" d f
  d="$(klab_arch_profiles_dir)"; f="$d/$arch.conf"; [[ -f "$f" ]] || return 1
  ( # shellcheck disable=SC1090
    source "$f"
    eval "printf '%s\\n' \"\${$field:-}\""
  )
}
klab_arch_ids(){
  local f id
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    id=""
    # shellcheck disable=SC1090
    source "$f"
    [[ -n "${ARCH_ID:-}" ]] && printf '%s\n' "$ARCH_ID"
  done < <(klab_arch_profile_files)
}
klab_arch_canonical(){
  local requested="$1" f id aliases a
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    id=""; aliases=""
    # shellcheck disable=SC1090
    source "$f"
    id="${ARCH_ID:-}"; aliases="${ARCH_ALIASES:-}"
    [[ "$requested" == "$id" ]] && { printf '%s\n' "$id"; return 0; }
    for a in $aliases; do [[ "$requested" == "$a" ]] && { printf '%s\n' "$id"; return 0; }; done
  done < <(klab_arch_profile_files)
  case "$requested" in
    x86_64|amd64) echo x86_64;; i386|i486|i586|i686|x86) echo i386;;
    aarch64|arm64) echo aarch64;; armv7|armv7l|armhf|arm) echo armv7;;
    mips) echo mips;; mipsel) echo mipsel;; mips64) echo mips64;; mips64el) echo mips64el;;
    *) return 1;;
  esac
}
klab_arch_host(){
  local raw="${KLAB_BUILD_ARCH_OVERRIDE:-$(uname -m)}"
  klab_arch_canonical "$raw" 2>/dev/null || printf '%s\n' "$raw"
}
klab_arch_status(){ klab_arch_profile_field "$(klab_arch_canonical "$1")" ARCH_STATUS 2>/dev/null || echo stable; }
klab_arch_assert_enabled(){
  local a status
  a="$(klab_arch_canonical "$1")" || return 1; status="$(klab_arch_status "$a")"
  case "$status" in
    stable|supported|'') return 0;;
    experimental) [[ "${KLAB_ENABLE_EXPERIMENTAL_ARCHES:-0}" == 1 ]];;
    disabled) return 1;;
    *) return 1;;
  esac
}
klab_arch_field(){ local a; a="$(klab_arch_canonical "$1")" || return 1; klab_arch_profile_field "$a" "$2"; }
klab_arch_kernel_arch(){ klab_arch_field "$1" KERNEL_ARCH; }
klab_arch_kernel_image(){ klab_arch_field "$1" KERNEL_IMAGE; }
klab_arch_kernel_defconfig(){ klab_arch_field "$1" KERNEL_DEFCONFIG; }
klab_arch_bits(){ klab_arch_field "$1" ARCH_BITS; }
klab_arch_endian(){ klab_arch_field "$1" ARCH_ENDIAN; }
klab_arch_abi(){ klab_arch_field "$1" ARCH_ABI; }
klab_arch_family(){ klab_arch_field "$1" ARCH_FAMILY; }
klab_arch_toolchain_target(){ klab_arch_field "$1" TOOLCHAIN_TARGET; }
klab_arch_qemu_binary(){ klab_arch_field "$1" QEMU_BINARY; }
klab_arch_qemu_machine(){ klab_arch_field "$1" QEMU_MACHINE; }
klab_arch_debian_name(){ klab_arch_field "$1" DEBIAN_ARCH; }
klab_arch_rpm_name(){ klab_arch_field "$1" RPM_ARCH; }
klab_arch_apk_name(){ klab_arch_field "$1" APK_ARCH; }
klab_arch_e2e_status(){ local a; a="$(klab_arch_canonical "$1")" || return 1; klab_arch_profile_field "$a" E2E_STATUS 2>/dev/null || echo disabled; }
klab_arch_e2e_versions(){ local a; a="$(klab_arch_canonical "$1")" || return 1; klab_arch_profile_field "$a" E2E_DEFAULT_VERSIONS 2>/dev/null || true; }
klab_arch_e2e_assert_enabled(){
  local a status
  a="$(klab_arch_canonical "$1")" || return 1; status="$(klab_arch_e2e_status "$a")"
  case "$status" in
    stable|supported) return 0;;
    experimental) [[ "${KLAB_ENABLE_EXPERIMENTAL_E2E:-0}" == 1 ]];;
    *) return 1;;
  esac
}

klab_arch_version_ge(){
  local have="$1" need="$2" first
  first="$(printf '%s\n%s\n' "$need" "$have" | LC_ALL=C sort -V | head -n1)"
  [[ "$first" == "$need" ]]
}
klab_arch_version_le(){ klab_arch_version_ge "$2" "$1"; }
klab_arch_kernel_version(){ printf '%s\n' "$1" | sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+([.][0-9]+)?).*/\1/p'; }
klab_arch_kernel_supported(){
  local a rel ver min max
  a="$(klab_arch_canonical "$1")" || return 1; rel="$2"; ver="$(klab_arch_kernel_version "$rel")"
  [[ -n "$ver" ]] || return 0
  min="$(klab_arch_profile_field "$a" KERNEL_MIN_VERSION 2>/dev/null || true)"
  max="$(klab_arch_profile_field "$a" KERNEL_MAX_VERSION 2>/dev/null || true)"
  [[ -z "$min" ]] || klab_arch_version_ge "$ver" "$min" || return 1
  [[ -z "$max" ]] || klab_arch_version_le "$ver" "$max" || return 1
  return 0
}
klab_arch_cross_required(){ local t b; t="$(klab_arch_canonical "$1")" || return 2; b="$(klab_arch_canonical "${2:-$(klab_arch_host)}" 2>/dev/null || printf '%s' "${2:-$(klab_arch_host)}")"; [[ "$t" != "$b" ]]; }

klab_arch_plan_json(){
  local target build status family bits endian abi karch tc qemu machine cross guest min rpm deb apk unamevals e2e ctlmode ctldev qmem qcpus netdev
  target="$(klab_arch_canonical "$1")" || return 1
  build="$(klab_arch_canonical "${2:-$(klab_arch_host)}" 2>/dev/null || printf '%s' "${2:-$(klab_arch_host)}")"
  status="$(klab_arch_status "$target")"; family="$(klab_arch_family "$target" 2>/dev/null || true)"; bits="$(klab_arch_bits "$target" 2>/dev/null || true)"
  endian="$(klab_arch_endian "$target" 2>/dev/null || true)"; abi="$(klab_arch_abi "$target" 2>/dev/null || true)"; karch="$(klab_arch_kernel_arch "$target" 2>/dev/null || true)"
  tc="$(klab_arch_toolchain_target "$target" 2>/dev/null || true)"; qemu="$(klab_arch_qemu_binary "$target" 2>/dev/null || true)"; machine="$(klab_arch_qemu_machine "$target" 2>/dev/null || true)"
  guest="$target"; e2e="$(klab_arch_e2e_status "$target" 2>/dev/null || echo disabled)"; ctlmode="$(klab_arch_profile_field "$target" QEMU_CONTROL_MODE 2>/dev/null || echo serial)"; ctldev="$(klab_arch_profile_field "$target" LINUX_CONTROL_TTY 2>/dev/null || true)"; qmem="$(klab_arch_profile_field "$target" QEMU_MEMORY 2>/dev/null || true)"; qcpus="$(klab_arch_profile_field "$target" QEMU_CPUS 2>/dev/null || true)"; netdev="$(klab_arch_profile_field "$target" QEMU_NET_DEVICE 2>/dev/null || true)"; min="$(klab_arch_profile_field "$target" KERNEL_MIN_VERSION 2>/dev/null || true)"; rpm="$(klab_arch_rpm_name "$target" 2>/dev/null || true)"; deb="$(klab_arch_debian_name "$target" 2>/dev/null || true)"; apk="$(klab_arch_apk_name "$target" 2>/dev/null || true)"; unamevals="$(klab_arch_profile_field "$target" GUEST_UNAME_MACHINE 2>/dev/null || true)"
  [[ "$target" == "$build" ]] && cross=false || cross=true
  python3 - "$target" "$build" "$guest" "$status" "$family" "$bits" "$endian" "$abi" "$karch" "$tc" "$qemu" "$machine" "$cross" "$min" "$rpm" "$deb" "$apk" "$unamevals" "$e2e" "$ctlmode" "$ctldev" "$qmem" "$qcpus" "$netdev" <<'PY'
import json,sys
(target,build,guest,status,family,bits,endian,abi,karch,tc,qemu,machine,cross,minver,rpm,deb,apk,unamevals,e2e,ctlmode,ctldev,qmem,qcpus,netdev)=sys.argv[1:]
def n(v): return v or None
print(json.dumps({
 "schema":"klab-arch-plan-v1",
 "model_version":1,
 "target_arch":target,
 "build_arch":build,
 "toolchain_exec_arch":build,
 "toolchain_target_arch":target,
 "guest_arch":guest,
 "cross_compile":cross=="true",
 "profile":{"status":status,"family":n(family),"bits":int(bits) if bits.isdigit() else None,"endian":n(endian),"abi":n(abi),"kernel_arch":n(karch),"kernel_min_version":n(minver)},
 "toolchain":{"target":n(tc)},
 "execution":{"qemu_binary":n(qemu),"qemu_machine":n(machine),"qemu_memory":n(qmem),"qemu_cpus":int(qcpus) if qcpus.isdigit() else None,"uname_machine":unamevals.split() if unamevals else [target],"e2e_status":e2e,"control_mode":ctlmode,"control_device":n(ctldev),"network_device":n(netdev)},
 "package_arch":{"debian":n(deb),"rpm":n(rpm),"apk":n(apk)}
},sort_keys=True))
PY
}
