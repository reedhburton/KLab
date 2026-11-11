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

# klab-buildroot-cache.sh
# Prepare, package, verify, and install an offline Buildroot source cache for
# Kernel Lab guest-userspace profiles. This does not compile Buildroot images;
# it configures each requested arch/profile and runs `make source` into one
# shared BR2_DL_DIR.

VERSION="3"
DEFAULT_BUILDROOT_VERSION="2025.02.18"
BUILDROOT_VERSION="${KLAB_BUILDROOT_VERSION:-$DEFAULT_BUILDROOT_VERSION}"
BUILDROOT_URL_BASE="${KLAB_BUILDROOT_URL_BASE:-https://buildroot.org/downloads}"
WORK_ROOT="${KLAB_BUILDROOT_CACHE_HOME:-$PWD/klab-buildroot-cache}"
ARCHES=(x86_64 i386 aarch64 armv7)
PROFILES=(minimal network)
JOBS="${KLAB_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ARCH_PROFILES_DIR="${KLAB_ARCH_PROFILES_DIR:-$SELF_DIR/architectures}"

say() { printf '\n==> %s\n' "$*" >&2; }
die() { printf 'klab-buildroot-cache: ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<'USAGE'
Usage:
  klab-buildroot-cache.sh create [options]
  klab-buildroot-cache.sh populate [options]
  klab-buildroot-cache.sh pack [options]
  klab-buildroot-cache.sh status [--work DIR]
  klab-buildroot-cache.sh verify FILE.tar.zst
  klab-buildroot-cache.sh inspect FILE.tar.zst
  klab-buildroot-cache.sh install FILE.tar.zst [--dest DIR]

Normal staging workflow:
  ./klab-buildroot-cache.sh create \
      --architectures x86_64,i386,aarch64,armv7 \
      --profiles minimal,network \
      -o klab-buildroot-sources-2025.02.18.tar.zst

Offline build host:
  ./klab-buildroot-cache.sh verify klab-buildroot-sources-2025.02.18.tar.zst
  ./klab-buildroot-cache.sh install klab-buildroot-sources-2025.02.18.tar.zst \
      --dest /srv/kernel-lab/work/buildroot

Then point Kernel Lab at /srv/kernel-lab (KLAB_ROOT=/srv/kernel-lab). The
installed cache lands in /srv/kernel-lab/work/buildroot/dl and the Buildroot source
tarball lands in /srv/kernel-lab/work/buildroot/downloads.

Validate the installed cache without network fallback:
  KLAB_ROOT=/srv/kernel-lab ./kernel-lab.sh buildroot-cache check --all

Options for create/populate/pack:
  --work DIR               Working/cache directory
  --buildroot-version VER  Buildroot release (default: 2025.02.18)
  --architectures LIST     Comma-separated architecture profile IDs (default: x86_64,i386,aarch64,armv7)
  --profiles LIST          Comma-separated: minimal,network
  -o, --output FILE        Output archive (create/pack)
  --jobs N                 Host make job count (configuration only; `source`
                           itself is handled by Buildroot)

Archive formats inferred from suffix:
  .tar.zst   recommended
  .tar.gz
  .tar.xz

Notes:
  * `populate` needs network access only for files not already in the shared dl/.
  * `pack` never uses the network.
  * `install` merges into an existing Buildroot dl/ cache; it does not delete
    files already present.
USAGE
}

arch_profile_files() { [[ -d "$ARCH_PROFILES_DIR" ]] && find "$ARCH_PROFILES_DIR" -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null | sort || true; }
arch_profile_field() { local arch="$1" field="$2" f="$ARCH_PROFILES_DIR/$arch.conf"; [[ -f "$f" ]] || return 1; (source "$f"; eval "printf '%s\n' \"\${$field:-}\""); }
canonical_arch() {
  local requested="$1" f id aliases a
  if [[ -d "$ARCH_PROFILES_DIR" ]]; then
    while IFS= read -r f; do id=""; aliases=""; source "$f"; id="${ARCH_ID:-}"; aliases="${ARCH_ALIASES:-}"; [[ "$requested" == "$id" ]] && { echo "$id"; return; }; for a in $aliases; do [[ "$requested" == "$a" ]] && { echo "$id"; return; }; done; done < <(arch_profile_files)
  fi
  case "$requested" in x86_64|amd64) echo x86_64 ;; i386|i486|i586|i686|x86) echo i386 ;; aarch64|arm64) echo aarch64 ;; armv7|armv7l|armhf|arm) echo armv7 ;; *) die "unsupported architecture '$requested'" ;; esac
}

validate_profile() {
  case "$1" in minimal|network|ssh) echo "$1" ;; *) die "unsupported profile '$1'" ;; esac
}

parse_csv_arches() {
  local csv="$1" item; ARCHES=()
  IFS=',' read -r -a _items <<< "$csv"
  for item in "${_items[@]}"; do ARCHES+=("$(canonical_arch "$item")"); done
}

parse_csv_profiles() {
  local csv="$1" item; PROFILES=()
  IFS=',' read -r -a _items <<< "$csv"
  for item in "${_items[@]}"; do PROFILES+=("$(validate_profile "$item")"); done
}

buildroot_defconfig_for_arch() {
  local a="$(canonical_arch "$1")" v=""
  v="$(arch_profile_field "$a" BUILDROOT_DEFCONFIG 2>/dev/null || true)"
  [[ -n "$v" ]] && { echo "$v"; return; }
  case "$a" in x86_64) echo qemu_x86_64_defconfig ;; i386) echo qemu_x86_defconfig ;; aarch64) echo qemu_aarch64_virt_defconfig ;; armv7) echo qemu_arm_vexpress_defconfig ;; *) die "no Buildroot defconfig mapping for '$a'" ;; esac
}

refresh_paths() {
  BR_HOME="$WORK_ROOT/buildroot"
  BR_DOWNLOADS="$BR_HOME/downloads"
  BR_ARCHIVE="$BR_DOWNLOADS/buildroot-$BUILDROOT_VERSION.tar.xz"
  BR_SRC="$BR_HOME/src/buildroot-$BUILDROOT_VERSION"
  BR_DL="$BR_HOME/dl"
  CONFIG_OUT="$WORK_ROOT/config-output"
  CONFIG_SNAP="$WORK_ROOT/configs"
  FRAGMENT="$WORK_ROOT/klab-busybox.fragment"
  PREPARED="$WORK_ROOT/PREPARED.env"
}
refresh_paths

need_tools() {
  local missing=() x
  for x in make gcc g++ patch perl python3 tar gzip bzip2 xz cpio unzip rsync file sed awk sha256sum find; do
    have "$x" || missing+=("$x")
  done
  if ! have curl && ! have wget; then missing+=(curl-or-wget); fi
  ((${#missing[@]} == 0)) || die "missing host tools: ${missing[*]}"
}

need_pack_tool() {
  local out="$1"
  case "$out" in
    *.tar.zst|*.tzst) have zstd || die "zstd is required for $out" ;;
    *.tar.gz|*.tgz) have gzip || die "gzip is required for $out" ;;
    *.tar.xz|*.txz) have xz || die "xz is required for $out" ;;
    *) die "output must end in .tar.zst, .tar.gz, or .tar.xz" ;;
  esac
}

download() {
  local url="$1" out="$2" tmp="$2.part.$$"
  mkdir -p "$(dirname "$out")"
  if have curl; then curl -fL --retry 3 --connect-timeout 20 -o "$tmp" "$url";
  else wget -O "$tmp" "$url"; fi
  mv "$tmp" "$out"
}

ensure_buildroot_source() {
  need_tools
  mkdir -p "$BR_DOWNLOADS" "$BR_HOME/src" "$BR_DL"
  if [[ ! -f "$BR_ARCHIVE" ]]; then
    say "Downloading Buildroot $BUILDROOT_VERSION"
    download "$BUILDROOT_URL_BASE/buildroot-$BUILDROOT_VERSION.tar.xz" "$BR_ARCHIVE" || die "failed to download Buildroot"
    download "$BUILDROOT_URL_BASE/buildroot-$BUILDROOT_VERSION.tar.xz.sign" "$BR_ARCHIVE.sign" >/dev/null 2>&1 || true
  fi
  if [[ ! -f "$BR_SRC/Makefile" ]]; then
    local tmp="$BR_HOME/src/.extract-$BUILDROOT_VERSION.$$"
    rm -rf "$tmp"; mkdir -p "$tmp"
    tar -xJf "$BR_ARCHIVE" -C "$tmp"
    [[ -f "$tmp/buildroot-$BUILDROOT_VERSION/Makefile" ]] || die "unexpected Buildroot archive layout"
    rm -rf "$BR_SRC"
    mv "$tmp/buildroot-$BUILDROOT_VERSION" "$BR_SRC"
    rm -rf "$tmp"
  fi
}

write_busybox_fragment() {
  mkdir -p "$(dirname "$FRAGMENT")"
  cat > "$FRAGMENT" <<'EOF_FRAGMENT'
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
EOF_FRAGMENT
}

br_config_bool() {
  local cfg="$1" sym="$2" val="$3"
  sed -i -e "/^${sym}=/d" -e "/^# ${sym} is not set$/d" "$cfg"
  if [[ "$val" == y ]]; then printf '%s=y\n' "$sym" >> "$cfg"; else printf '# %s is not set\n' "$sym" >> "$cfg"; fi
}

br_config_string() {
  local cfg="$1" sym="$2" val="$3" escaped
  sed -i -e "/^${sym}=/d" -e "/^# ${sym} is not set$/d" "$cfg"
  escaped="${val//\\/\\\\}"; escaped="${escaped//\"/\\\"}"
  printf '%s="%s"\n' "$sym" "$escaped" >> "$cfg"
}

configure_one() {
  local arch="$1" profile="$2" defcfg out cfg snap
  defcfg="$(buildroot_defconfig_for_arch "$arch")"
  out="$CONFIG_OUT/$profile/$arch"
  cfg="$out/.config"
  snap="$CONFIG_SNAP/$profile/$arch.config"
  mkdir -p "$out" "$(dirname "$snap")"

  say "Configuring $profile / $arch ($defcfg)"
  make -s -C "$BR_SRC" O="$out" BR2_DL_DIR="$BR_DL" "$defcfg" || die "Buildroot defconfig failed for $arch/$profile"

  # Keep this aligned with Kernel Lab v13's Buildroot userspace profile.
  br_config_bool "$cfg" BR2_LINUX_KERNEL n
  br_config_bool "$cfg" BR2_TARGET_ROOTFS_EXT2 n
  br_config_bool "$cfg" BR2_TARGET_ROOTFS_TAR y
  br_config_bool "$cfg" BR2_PACKAGE_HOST_QEMU n
  br_config_bool "$cfg" BR2_PACKAGE_HOST_QEMU_SYSTEM_MODE n
  br_config_bool "$cfg" BR2_INIT_NONE y
  br_config_bool "$cfg" BR2_INIT_BUSYBOX n
  br_config_bool "$cfg" BR2_PACKAGE_BUSYBOX y
  br_config_bool "$cfg" BR2_TOOLCHAIN_BUILDROOT_UCLIBC n
  br_config_bool "$cfg" BR2_TOOLCHAIN_BUILDROOT_GLIBC n
  br_config_bool "$cfg" BR2_TOOLCHAIN_BUILDROOT_MUSL y
  br_config_bool "$cfg" BR2_STATIC_LIBS y
  br_config_bool "$cfg" BR2_PACKAGE_HOST_ENVIRONMENT_SETUP y
  br_config_string "$cfg" BR2_GLOBAL_PATCH_DIR ""
  br_config_string "$cfg" BR2_SYSTEM_DHCP ""
  br_config_string "$cfg" BR2_ROOTFS_POST_BUILD_SCRIPT ""
  br_config_string "$cfg" BR2_ROOTFS_POST_IMAGE_SCRIPT ""
  br_config_string "$cfg" BR2_ROOTFS_POST_SCRIPT_ARGS ""
  br_config_string "$cfg" BR2_PACKAGE_BUSYBOX_CONFIG_FRAGMENT_FILES "$FRAGMENT"

  if [[ "$profile" == network || "$profile" == ssh ]]; then
    br_config_bool "$cfg" BR2_PACKAGE_IPROUTE2 y
    br_config_bool "$cfg" BR2_PACKAGE_ETHTOOL y
    br_config_bool "$cfg" BR2_PACKAGE_IPERF3 y
    br_config_bool "$cfg" BR2_PACKAGE_TCPDUMP y
    br_config_bool "$cfg" BR2_PACKAGE_IPUTILS y
    br_config_bool "$cfg" BR2_PACKAGE_IPUTILS_PING y
    br_config_bool "$cfg" BR2_PACKAGE_IPUTILS_TRACEPATH y
  fi
  if [[ "$profile" == ssh ]]; then
    br_config_bool "$cfg" BR2_PACKAGE_DROPBEAR y
    br_config_bool "$cfg" BR2_PACKAGE_DROPBEAR_CLIENT n
  fi

  make -s -C "$BR_SRC" O="$out" BR2_DL_DIR="$BR_DL" olddefconfig || die "olddefconfig failed for $arch/$profile"
  cp "$cfg" "$snap"

  say "Downloading selected sources for $profile / $arch"
  make -C "$BR_SRC" O="$out" BR2_DL_DIR="$BR_DL" source || die "make source failed for $arch/$profile"
  cp "$cfg" "$snap"
}

write_prepared_manifest() {
  local arch_csv profile_csv
  arch_csv="$(IFS=,; echo "${ARCHES[*]}")"
  profile_csv="$(IFS=,; echo "${PROFILES[*]}")"
  cat > "$PREPARED" <<EOF_PREPARED
KLAB_BUILDROOT_CACHE_FORMAT=1
KLAB_BUILDROOT_VERSION=$BUILDROOT_VERSION
KLAB_BUILDROOT_ARCHES=$arch_csv
KLAB_BUILDROOT_PROFILES=$profile_csv
KLAB_BUILDROOT_CREATED_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
KLAB_BUILDROOT_DL=$BR_DL
EOF_PREPARED
}

cmd_populate() {
  ensure_buildroot_source
  write_busybox_fragment
  local profile arch
  for profile in "${PROFILES[@]}"; do
    for arch in "${ARCHES[@]}"; do
      configure_one "$arch" "$profile"
    done
  done
  write_prepared_manifest
  say "Source cache populated"
  du -sh "$BR_DL" >&2 || true
}

make_sha_file() {
  local stage="$1" sha="$stage/SHA256SUMS" f rel
  : > "$sha"
  while IFS= read -r -d '' f; do
    rel="${f#$stage/}"
    [[ "$rel" == SHA256SUMS ]] && continue
    (cd "$stage" && sha256sum "$rel") >> "$sha"
  done < <(find "$stage" -type f -print0 | sort -z)

  while IFS= read -r -d '' f; do
    rel="dl/${f#$BR_DL/}"
    printf '%s  %s\n' "$(sha256sum "$f" | awk '{print $1}')" "$rel" >> "$sha"
  done < <(find "$BR_DL" -type f -print0 | sort -z)
}

write_json_manifest() {
  local stage="$1" arch_json profile_json cache_bytes cache_files
  arch_json="$(printf '%s\n' "${ARCHES[@]}" | python3 -c 'import json,sys; print(json.dumps([x.strip() for x in sys.stdin if x.strip()]))')"
  profile_json="$(printf '%s\n' "${PROFILES[@]}" | python3 -c 'import json,sys; print(json.dumps([x.strip() for x in sys.stdin if x.strip()]))')"
  cache_bytes="$(du -sb "$BR_DL" 2>/dev/null | awk '{print $1}' || echo 0)"
  cache_files="$(find "$BR_DL" -type f | wc -l | awk '{print $1}')"
  cat > "$stage/manifest.json" <<EOF_JSON
{
  "format": "klab-buildroot-source-cache",
  "format_version": 1,
  "buildroot_version": "$BUILDROOT_VERSION",
  "architectures": $arch_json,
  "profiles": $profile_json,
  "cache_files": $cache_files,
  "cache_bytes": $cache_bytes,
  "created_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "purpose": "Offline Buildroot make source cache for Kernel Lab guest userspaces"
}
EOF_JSON
}

archive_create() {
  local stage="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  case "$out" in
    *.tar.zst|*.tzst)
      tar -cf - -C "$stage" . -C "$BR_HOME" dl | zstd -T0 -19 -q -o "$out"
      ;;
    *.tar.gz|*.tgz)
      tar -cf - -C "$stage" . -C "$BR_HOME" dl | gzip -9 > "$out"
      ;;
    *.tar.xz|*.txz)
      tar -cf - -C "$stage" . -C "$BR_HOME" dl | xz -T0 -6 > "$out"
      ;;
  esac
}

extract_archive() {
  local archive="$1" dest="$2"
  mkdir -p "$dest"
  case "$archive" in
    *.tar.zst|*.tzst) have zstd || die "zstd required to read $archive"; zstd -dc "$archive" | tar -xf - -C "$dest" ;;
    *.tar.gz|*.tgz) gzip -dc "$archive" | tar -xf - -C "$dest" ;;
    *.tar.xz|*.txz) xz -dc "$archive" | tar -xf - -C "$dest" ;;
    *) die "unsupported archive suffix: $archive" ;;
  esac
}

cmd_pack() {
  local out="$1"
  [[ -f "$PREPARED" ]] || die "cache has not been populated; run populate first"
  [[ -d "$BR_DL" ]] || die "missing Buildroot dl cache: $BR_DL"
  [[ -f "$BR_ARCHIVE" ]] || die "missing Buildroot source archive: $BR_ARCHIVE"
  need_pack_tool "$out"

  local stage="$WORK_ROOT/.pack.$$"
  rm -rf "$stage"; mkdir -p "$stage/buildroot" "$stage/configs"
  trap 'rm -rf "$stage"' RETURN

  printf '1\n' > "$stage/FORMAT_VERSION"
  cp "$PREPARED" "$stage/manifest.env"
  cp "$BR_ARCHIVE" "$stage/buildroot/"
  [[ -f "$BR_ARCHIVE.sign" ]] && cp "$BR_ARCHIVE.sign" "$stage/buildroot/"
  cp "$FRAGMENT" "$stage/klab-busybox.fragment"
  cp -a "$CONFIG_SNAP/." "$stage/configs/"
  write_json_manifest "$stage"
  cat > "$stage/README.txt" <<'EOF_README'
Kernel Lab Buildroot source-cache bundle

This archive contains a shared Buildroot BR2_DL_DIR populated with `make source`
for the architectures/profiles listed in manifest.json, plus the pinned Buildroot
source tarball and configuration snapshots used to determine the source set.

The configs/ files are audit snapshots; Kernel Lab regenerates its active
Buildroot configuration when it builds a guest userspace. Install this cache into
<KLAB_ROOT>/work/buildroot with klab-buildroot-cache.sh install.
EOF_README
  make_sha_file "$stage"

  say "Packing $out"
  archive_create "$stage" "$out"
  say "Created $(du -h "$out" | awk '{print $1}') archive: $out"
  rm -rf "$stage"; trap - RETURN
}

cmd_verify() {
  local archive="$1" tmp
  [[ -f "$archive" ]] || die "not found: $archive"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  extract_archive "$archive" "$tmp"
  [[ "$(cat "$tmp/FORMAT_VERSION" 2>/dev/null || true)" == 1 ]] || die "unsupported or missing cache format"
  [[ -f "$tmp/SHA256SUMS" ]] || die "archive lacks SHA256SUMS"
  (cd "$tmp" && sha256sum -c SHA256SUMS >/dev/null) || die "checksum verification failed"
  say "Cache archive verified"
  rm -rf "$tmp"; trap - RETURN
}

cmd_inspect() {
  local archive="$1" tmp
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  extract_archive "$archive" "$tmp"
  if [[ -f "$tmp/manifest.json" ]]; then cat "$tmp/manifest.json"; else cat "$tmp/manifest.env"; fi
  printf '\nArchive size: '; du -h "$archive" | awk '{print $1}'
  printf 'Extracted dl size: '; du -sh "$tmp/dl" | awk '{print $1}'
  rm -rf "$tmp"; trap - RETURN
}

cmd_install() {
  local archive="$1" dest="$2" tmp version src_archive
  cmd_verify "$archive"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  extract_archive "$archive" "$tmp"
  version="$(python3 - "$tmp/manifest.json" <<'PY'
import json,sys
print(json.load(open(sys.argv[1]))['buildroot_version'])
PY
)"
  mkdir -p "$dest/dl" "$dest/downloads" "$dest/cache-configs/$version"
  say "Merging source downloads into $dest/dl"
  rsync -a "$tmp/dl/" "$dest/dl/"
  src_archive="$tmp/buildroot/buildroot-$version.tar.xz"
  [[ -f "$src_archive" ]] || die "archive lacks Buildroot source tarball"
  cp "$src_archive" "$dest/downloads/"
  [[ -f "$src_archive.sign" ]] && cp "$src_archive.sign" "$dest/downloads/"
  cp -a "$tmp/configs/." "$dest/cache-configs/$version/"
  cp "$tmp/manifest.json" "$dest/cache-configs/$version/manifest.json"
  cp "$tmp/klab-busybox.fragment" "$dest/cache-configs/$version/klab-busybox.fragment"
  say "Installed Buildroot $version source cache"
  du -sh "$dest/dl" >&2 || true
  printf 'Next: KLAB_ROOT=%q ./kernel-lab.sh buildroot-cache check --all\n' "$KLAB_ROOT" >&2
  rm -rf "$tmp"; trap - RETURN
}

cmd_status() {
  printf 'Work root:          %s\n' "$WORK_ROOT"
  printf 'Buildroot version:  %s\n' "$BUILDROOT_VERSION"
  printf 'Architectures:      %s\n' "$(IFS=,; echo "${ARCHES[*]}")"
  printf 'Profiles:           %s\n' "$(IFS=,; echo "${PROFILES[*]}")"
  if [[ -f "$BR_ARCHIVE" ]]; then printf 'Buildroot archive:  ready\n'; else printf 'Buildroot archive:  missing\n'; fi
  if [[ -f "$BR_SRC/Makefile" ]]; then printf 'Buildroot source:   ready\n'; else printf 'Buildroot source:   missing\n'; fi
  if [[ -d "$BR_DL" ]]; then
    printf 'Download cache:     %s (%s files)\n' "$(du -sh "$BR_DL" | awk '{print $1}')" "$(find "$BR_DL" -type f | wc -l | awk '{print $1}')"
  else printf 'Download cache:     missing\n'; fi
  [[ -f "$PREPARED" ]] && { printf '\nPrepared manifest:\n'; cat "$PREPARED"; }
}

parse_common_options() {
  OUTPUT=""
  while (($#)); do
    case "$1" in
      --work) [[ $# -ge 2 ]] || die "--work needs a value"; WORK_ROOT="$2"; shift 2; refresh_paths ;;
      --buildroot-version) [[ $# -ge 2 ]] || die "--buildroot-version needs a value"; BUILDROOT_VERSION="$2"; shift 2; refresh_paths ;;
      --architectures|--arches) [[ $# -ge 2 ]] || die "$1 needs a value"; parse_csv_arches "$2"; shift 2 ;;
      --profiles) [[ $# -ge 2 ]] || die "--profiles needs a value"; parse_csv_profiles "$2"; shift 2 ;;
      --jobs) [[ $# -ge 2 ]] || die "--jobs needs a value"; JOBS="$2"; shift 2 ;;
      -o|--output) [[ $# -ge 2 ]] || die "$1 needs a value"; OUTPUT="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
  done
}

main() {
  (($#)) || { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    create)
      parse_common_options "$@"
      [[ -n "$OUTPUT" ]] || OUTPUT="$PWD/klab-buildroot-sources-$BUILDROOT_VERSION.tar.zst"
      cmd_populate
      cmd_pack "$OUTPUT"
      ;;
    populate)
      parse_common_options "$@"
      cmd_populate
      ;;
    pack)
      parse_common_options "$@"
      [[ -n "$OUTPUT" ]] || OUTPUT="$PWD/klab-buildroot-sources-$BUILDROOT_VERSION.tar.zst"
      cmd_pack "$OUTPUT"
      ;;
    status)
      while (($#)); do case "$1" in --work) WORK_ROOT="$2"; shift 2; refresh_paths ;; --buildroot-version) BUILDROOT_VERSION="$2"; shift 2; refresh_paths ;; *) die "unknown option: $1" ;; esac; done
      cmd_status
      ;;
    verify)
      (($# == 1)) || die "usage: $0 verify FILE"
      cmd_verify "$1"
      ;;
    inspect)
      (($# == 1)) || die "usage: $0 inspect FILE"
      cmd_inspect "$1"
      ;;
    install)
      (($# >= 1)) || die "usage: $0 install FILE [--dest DIR]"
      local archive="$1" dest="${KLAB_BUILDROOT_DEST:-$KLAB_WORK/buildroot}"; shift
      while (($#)); do case "$1" in --dest) [[ $# -ge 2 ]] || die "--dest needs a value"; dest="$2"; shift 2 ;; *) die "unknown option: $1" ;; esac; done
      cmd_install "$archive" "$dest"
      ;;
    -h|--help|help) usage ;;
    *) die "unknown command '$cmd'" ;;
  esac
}

main "$@"
