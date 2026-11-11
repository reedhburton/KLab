#!/usr/bin/env bash
set -Eeuo pipefail

# KLAB_UNIFIED_ROOT_R22
# KLAB_NATIVE_PATHS_R23
# KLAB_RESIDUAL_PATH_AUDIT_R24
_KLAB_SELF_PATH="${BASH_SOURCE[0]:-$0}"
_KLAB_SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$_KLAB_SELF_PATH")" && pwd)"
if [[ -f "$_KLAB_SELF_DIR/lib/klab-root.sh" ]]; then
  # shellcheck source=lib/klab-root.sh
  source "$_KLAB_SELF_DIR/lib/klab-root.sh"
  klab_root_ensure_layout
fi
unset _KLAB_SELF_DIR _KLAB_SELF_PATH

# klab-bundle.sh - create, verify, inspect, and import kernel-lab air-gap bundles.
#
# .klab is a kernel-lab-specific interchange format (not an upstream Linux
# standard). Format v1 is a zstd-compressed tar archive containing a versioned
# JSON manifest, SHA-256 checksums, and one or more independently compressed
# payloads.

FORMAT_NAME="kernel-lab-bundle"
FORMAT_VERSION=1
LAB_HOME="$KLAB_ROOT"
KERNELS="$KLAB_TARGETS/kernels"
TOOLCHAINS="$KLAB_TOOLCHAIN_STORE"
SRC="$KLAB_CACHE/linux"
BUILDS="$KLAB_WORK/builds"
SOURCES="$KLAB_CACHE/sources"
GUESTS="$KLAB_USERSPACE_STORE"
BUILDROOT_VERSION="${KLAB_BUILDROOT_VERSION:-2025.02.18}"
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ARCH_PROFILES_DIR="${KLAB_ARCH_PROFILES_DIR:-$SELF_DIR/architectures}"
ARCH_MODEL_BIN="${KLAB_ARCH_MODEL_BIN:-$SELF_DIR/lib/arch-model.sh}"
[[ -f "$ARCH_MODEL_BIN" ]] || { echo "klab-bundle: ERROR: architecture model missing: $ARCH_MODEL_BIN" >&2; exit 1; }
# shellcheck source=lib/arch-model.sh
source "$ARCH_MODEL_BIN"

arch_profile_files() { klab_arch_profile_files; }
arch_profile_field() { klab_arch_profile_field "$1" "$2"; }
canonical_arch() { local a; a="$(klab_arch_canonical "$1" 2>/dev/null || true)"; [[ -n "$a" ]] || die "unsupported architecture '$1'"; printf '%s\n' "$a"; }
linux_kernel_image_rel() { local a; a="$(canonical_arch "$1")"; klab_arch_kernel_image "$a" 2>/dev/null || die "architecture $a has no kernel image mapping"; }

ARCH="$(canonical_arch "${KLAB_ARCH:-x86_64}")"
CONTAINER_RUNTIME="${KLAB_CONTAINER_RUNTIME:-}"
KERNEL_LAB_BIN="${KLAB_KERNEL_LAB_BIN:-$SELF_DIR/kernel-lab.sh}"
TOOLCHAIN_BOUNDARY_BIN="${KLAB_TOOLCHAIN_BOUNDARY_BIN:-$SELF_DIR/klab-toolchain-boundary.sh}" # KLAB_TOOLCHAIN_BOUNDARY_M2
BUILDENV_BIN="${KLAB_BUILDENV_BIN:-$SELF_DIR/klab-buildenv.sh}" # KLAB_BUILDENV_TRANSFER_M2

say() { printf '\n==> %s\n' "$*" >&2; }
die() { printf 'klab-bundle: ERROR: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
remove_tree() {
  local path="${1:-}"
  [[ -n "$path" && -e "$path" ]] || return 0
  chmod -R u+w "$path" 2>/dev/null || true
  rm -rf -- "$path"
}

# A stable toolchain name describes compiler provenance, not archive identity.
# Older bundles can legitimately carry different relocatable archives under the
# same name. Keep the original path for the first archive and content-address
# later variants instead of allowing --force to invalidate earlier targets.
toolchain_import_dest() {
  local store="$1" id="$2" archive_sha="$3"
  local primary="$store/$id" marker="$store/$id/.klab-toolchain.sha256"
  if [[ ! -d "$primary" || ( -f "$marker" && "$(cat "$marker")" == "$archive_sha" ) ]]; then
    printf '%s\n' "$primary"
  else
    printf '%s\n' "$store/$id--$archive_sha"
  fi
}

usage() {
  cat <<'USAGE'
Usage:
  klab-bundle.sh create <target> [-o FILE.klab] [--profile PROFILE]
                         [--include-toolchain DIR | --auto-toolchain]
                         [--toolchain-id ID] [--toolchain-cc RELPATH]
                         [--include-image IMAGE] [--userspace busybox-static|buildroot:minimal|buildroot:network|buildroot:ssh|native:PROVIDER:RELEASE] [--include-sdk]
  klab-bundle.sh export <target> [same options as create]
  klab-bundle.sh verify <FILE.klab>
  klab-bundle.sh inspect <FILE.klab>
  klab-bundle.sh import <FILE.klab> [--force] [--load-image]

Targets:
  ubuntu:22.04:6.8.0-139-generic
  debian:bookworm:6.1.0-40-amd64
  fedora:43:6.17.1-300.fc43.x86_64
  centos:stream9:5.14.0-...el9.x86_64
  rhel:9:5.14.0-...el9.x86_64
  upstream:v6.6
  upstream:mainline
  freebsd:15.1-RELEASE:x86_64
  freebsd:15.1-RELEASE:aarch64
  custom:vendor-name:kernel-release
  upstream:v6.6   # use KLAB_ARCH=i386 or armv7 for 32-bit upstream bundles

Notes:
  * Distro targets must already have been fetched by kernel-lab.sh.
  * Upstream targets must already have been built by kernel-lab.sh.
  * --profile applies to upstream targets (default: normal).
  * --include-toolchain archives and BINDS a toolchain to this kernel target.
    The importer installs it in $KLAB_TOOLCHAIN_STORE/<id> (or a content-addressed sibling when the logical ID is reused), and kernel-lab
    automatically uses it for external-module builds.
  * --auto-toolchain asks kernel-lab to inspect the cached target's compiler,
    download/cache a matching kernel.org GCC toolchain (exact version when
    available; otherwise newest release in the same GCC major), and bind it.
  * --toolchain-id overrides the detected stable ID.
  * --toolchain-cc identifies the compiler executable relative to the toolchain
    root (for example bin/x86_64-linux-gcc). If omitted, it is auto-detected.
  * --include-image saves a Podman/Docker image into the bundle. Use this for
    a pre-built offline builder image if your isolated lab uses containers.
  * import never needs network access.

Guest userspace:
  Linux bundles carry the selected guest userspace. v15 supports the legacy
  architecture-matched static BusyBox plus pinned Buildroot minimal/network/ssh rootfs profiles.
  --include-sdk carries the matching relocatable Buildroot SDK for offline C test builds.

Architecture:
  Bundles carry an explicit canonical architecture.

Environment:
  KLAB_ROOT, KLAB_ARCH, KLAB_CONTAINER_RUNTIME, KLAB_KERNEL_LAB_BIN
USAGE
}

need_common() {
  local x
  for x in tar zstd sha256sum python3; do
    have "$x" || die "required program not found: $x"
  done
}

validate_token() {
  [[ "$1" =~ ^[A-Za-z0-9._+~@-]+$ ]] || die "invalid $2 '$1'"
}

parse_target() {
  local target="$1" extra=""
  PROVIDER=""; DISTRO_RELEASE=""; KERNEL_RELEASE=""
  IFS=: read -r PROVIDER DISTRO_RELEASE KERNEL_RELEASE extra <<<"$target"
  [[ -n "$PROVIDER" && -n "$DISTRO_RELEASE" ]] || die "invalid target '$target'"
  [[ -z "$extra" ]] || die "invalid target '$target': too many ':' fields"
  validate_token "$PROVIDER" provider
  validate_token "$DISTRO_RELEASE" release
  [[ -z "$KERNEL_RELEASE" ]] || validate_token "$KERNEL_RELEASE" kernel-release
}

bundle_dir_for() {
  local provider="$1" release="$2" krel="$3" arch="$(canonical_arch "${4:-$ARCH}")"
  printf '%s/%s/%s/%s/%s\n' "$KERNELS" "$provider" "${release//@/_}" "$arch" "$krel"
}

legacy_bundle_dir_for() {
  printf '%s/%s/%s/%s\n' "$KERNELS" "$1" "${2//@/_}" "$3"
}

bundle_existing_dir_for() {
  local provider="$1" release="$2" krel="$3" arch="$(canonical_arch "${4:-$ARCH}")" modern legacy
  modern="$(bundle_dir_for "$provider" "$release" "$krel" "$arch")"
  legacy="$(legacy_bundle_dir_for "$provider" "$release" "$krel")"
  if [[ -f "$modern/bundle.env" ]]; then printf '%s\n' "$modern"
  elif [[ "$arch" == x86_64 && -f "$legacy/bundle.env" ]]; then printf '%s\n' "$legacy"
  else printf '%s\n' "$modern"; fi
}

guest_busybox_path() { printf '%s/busybox/%s/busybox\n' "$GUESTS" "$(canonical_arch "$1")"; }
normalize_userspace_spec() {
  case "${1:-busybox-static}" in
    busybox|busybox-static|minimal-busybox) echo busybox-static ;;
    buildroot|buildroot:minimal) echo buildroot:minimal ;;
    buildroot:network|buildroot-network) echo buildroot:network ;;
    buildroot:ssh|buildroot-ssh) echo buildroot:ssh ;;
    native:ubuntu:*|native:debian:*|native:fedora:*|native:centos:*|native:alpine:*|native:arch:*) echo "$1" ;;
    *) die "unsupported guest userspace '$1'" ;;
  esac
}
buildroot_guest_dir() { printf '%s/buildroot/%s/%s/%s\n' "$GUESTS" "$BUILDROOT_VERSION" "${2:-minimal}" "$(canonical_arch "$1")"; }
buildroot_rootfs_path() { printf '%s/rootfs.tar\n' "$(buildroot_guest_dir "$1" "${2:-minimal}")"; }
buildroot_guest_metadata_path() { printf '%s/metadata.env\n' "$(buildroot_guest_dir "$1" "${2:-minimal}")"; }
native_rootfs_path() { printf '%s/native/%s/%s/%s/rootfs.tar.zst\n' "$GUESTS" "$1" "$2" "$(canonical_arch "$3")"; }
native_metadata_path() { printf '%s/native/%s/%s/%s/metadata.env\n' "$GUESTS" "$1" "$2" "$(canonical_arch "$3")"; }
buildroot_sdk_archive_path() { printf '%s/sdk.tar.gz\n' "$(buildroot_guest_dir "$1" "${2:-minimal}")"; }

json_get() {
  local file="$1" expr="$2"
  python3 - "$file" "$expr" <<'PY'
import json,sys
p,expr=sys.argv[1:]
with open(p,'r',encoding='utf-8') as f: o=json.load(f)
cur=o
for k in expr.split('.'):
    if not k: continue
    if isinstance(cur, list): cur=cur[int(k)]
    else: cur=cur[k]
if cur is None: print('')
elif isinstance(cur,(dict,list)): print(json.dumps(cur,sort_keys=True))
else: print(cur)
PY
}

sha256_file() { sha256sum "$1" | awk '{print $1}'; }

sanitize_id() {
  printf '%s' "$1" | tr -cs 'A-Za-z0-9._+-' '-'
}

detect_toolchain_cc() {
  local root="$1" requested="${2:-}" cc=""
  if [[ -n "$requested" ]]; then
    if [[ "$requested" = /* ]]; then cc="$requested"; else cc="$root/$requested"; fi
    [[ -x "$cc" ]] || die "toolchain compiler is not executable: $cc"
  else
    # Prefer prefixed GCC (kernel.org crosstool layout), then native GCC, then Clang.
    cc="$(find "$root" -maxdepth 5 \( -type f -o -type l \) -perm -111 -path '*/bin/*' -name '*-gcc' -print 2>/dev/null | sort | head -n1 || true)"
    [[ -n "$cc" ]] || cc="$(find "$root" -maxdepth 5 \( -type f -o -type l \) -perm -111 -path '*/bin/gcc' -print 2>/dev/null | sort | head -n1 || true)"
    [[ -n "$cc" ]] || cc="$(find "$root" -maxdepth 5 \( -type f -o -type l \) -perm -111 -path '*/bin/*' \( -name 'clang' -o -name 'clang-[0-9]*' \) -print 2>/dev/null | sort | head -n1 || true)"
    [[ -n "$cc" ]] || die "could not auto-detect gcc/clang under a bin/ directory in $root; use --toolchain-cc RELPATH"
  fi
  case "$cc" in "$root"/*) ;; *) die "toolchain compiler must live under the included toolchain root" ;; esac
  printf '%s\n' "$cc"
}

probe_toolchain_json() {
  local root="$1" archive_sha="$2" id_override="${3:-}" cc_request="${4:-}"
  local cc rel family version target base prefix_rel="" id bin_rel
  cc="$(detect_toolchain_cc "$root" "$cc_request")"
  rel="${cc#"$root"/}"
  base="$(basename "$cc")"
  bin_rel="$(dirname "$rel")"
  case "$base" in
    *gcc*)
      family=gcc
      version="$($cc -dumpfullversion -dumpversion 2>/dev/null | head -n1)"
      [[ -n "$version" ]] || version="$($cc -dumpversion 2>/dev/null | head -n1)"
      target="$($cc -dumpmachine 2>/dev/null | head -n1 || true)"
      if [[ "$base" == *-gcc ]]; then prefix_rel="${rel%gcc}"; fi
      ;;
    clang*)
      family=clang
      version="$($cc --version 2>/dev/null | sed -n '1s/.*clang version \([^ ]*\).*/\1/p')"
      [[ -n "$version" ]] || version="$($cc --version 2>/dev/null | head -n1)"
      target="$($cc -dumpmachine 2>/dev/null | head -n1 || true)"
      ;;
    *) die "unsupported bound compiler: $cc" ;;
  esac
  [[ -n "$version" ]] || die "could not determine compiler version for $cc"
  [[ -n "$target" ]] || target=unknown
  if [[ -n "$id_override" ]]; then
    id="$(sanitize_id "$id_override")"
  else
    id="$(sanitize_id "${family}-${version}-${target}")"
  fi
  [[ -n "$id" ]] || die "empty toolchain id"
  local resolver_source="" requested_version="" source_url="" download_sha="" target_compiler_family="" target_compiler_version="" target_compiler_banner=""
  if [[ -f "$root/.klab-resolver.env" ]]; then
    unset KLAB_TOOLCHAIN_SOURCE KLAB_TOOLCHAIN_REQUESTED_VERSION KLAB_TOOLCHAIN_URL KLAB_TOOLCHAIN_DOWNLOAD_SHA256
    # shellcheck disable=SC1090
    source "$root/.klab-resolver.env"
    resolver_source="${KLAB_TOOLCHAIN_SOURCE:-}"
    requested_version="${KLAB_TOOLCHAIN_REQUESTED_VERSION:-}"
    source_url="${KLAB_TOOLCHAIN_URL:-}"
    download_sha="${KLAB_TOOLCHAIN_DOWNLOAD_SHA256:-}"
  fi
  if [[ -f "$root/.klab-last-resolution.env" ]]; then
    unset KLAB_TARGET_COMPILER_FAMILY KLAB_TARGET_COMPILER_VERSION KLAB_TARGET_COMPILER_BANNER
    # shellcheck disable=SC1090
    source "$root/.klab-last-resolution.env"
    target_compiler_family="${KLAB_TARGET_COMPILER_FAMILY:-}"
    target_compiler_version="${KLAB_TARGET_COMPILER_VERSION:-}"
    target_compiler_banner="${KLAB_TARGET_COMPILER_BANNER:-}"
  fi
  python3 - "$archive_sha" "$id" "$(basename "$root")" "$rel" "$family" "$version" "$target" "$prefix_rel" "$bin_rel" "$resolver_source" "$requested_version" "$source_url" "$download_sha" "$target_compiler_family" "$target_compiler_version" "$target_compiler_banner" <<'PYTCMETA'
import json,sys
(sha,tid,name,cc,fam,ver,target,prefix,bindir,source,requested,url,dsha,tfam,tver,tbanner)=sys.argv[1:]
o={
  "path":"extras/toolchain.tar.zst",
  "sha256":sha,
  "id":tid,
  "name":name,
  "bound":True,
  "cc_relpath":cc,
  "family":fam,
  "version":ver,
  "target":target,
  "cross_prefix_relpath":prefix or None,
  "bin_dir_relpath":bindir or "."
}
if source: o["resolver_source"]=source
if requested: o["requested_version"]=requested
if url: o["source_url"]=url
if dsha: o["download_sha256"]=dsha
if tfam or tver or tbanner:
    o["target_compiler"]={"family":tfam or None,"version":tver or None,"banner":tbanner or None}
print(json.dumps(o))
PYTCMETA
}

container_runtime() {
  if [[ -n "$CONTAINER_RUNTIME" ]]; then
    have "$CONTAINER_RUNTIME" || die "KLAB_CONTAINER_RUNTIME '$CONTAINER_RUNTIME' not found"
    printf '%s\n' "$CONTAINER_RUNTIME"
  elif have podman; then
    printf '%s\n' podman
  elif have docker; then
    printf '%s\n' docker
  else
    die "--include-image requires podman or docker"
  fi
}

safe_name() { printf '%s' "$1" | tr ':@/' '___'; }

find_upstream_build() {
  local raw="$1" profile="$2" arch="$(canonical_arch "${3:-$ARCH}")" version key legacy
  case "$raw" in
    mainline|master)
      key="$(find "$BUILDS" -mindepth 1 -maxdepth 1 -type d -name "mainline-*__${arch}__${profile}" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)"
      if [[ -z "$key" && "$arch" == x86_64 ]]; then
        key="$(find "$BUILDS" -mindepth 1 -maxdepth 1 -type d -name "mainline-*__${profile}" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)"
      fi
      [[ -n "$key" ]] || die "no cached mainline/$arch/$profile build found; run kernel-lab.sh build mainline $profile with KLAB_ARCH=$arch"
      printf '%s\n' "$key"
      ;;
    v*) version="${raw#v}" ;;
    *) version="$raw" ;;
  esac
  if [[ "$raw" != mainline && "$raw" != master ]]; then
    key="$BUILDS/${version}__${arch}__${profile}"
    legacy="$BUILDS/${version}__${profile}"
    local imported="$KERNELS/upstream/$version/$arch/$profile/build"
    if [[ -d "$key" ]]; then printf '%s\n' "$key"
    elif [[ "$arch" == x86_64 && -d "$legacy" ]]; then printf '%s\n' "$legacy"
    elif [[ -d "$imported" ]]; then printf '%s\n' "$imported"
    else die "no cached or imported upstream build $raw/$arch/$profile; run kernel-lab.sh prepare/build or import a .klab first"; fi
  fi
}

upstream_ref_for() {
  case "$1" in
    mainline|master)
      local build="$2" commit=""
      [[ -f "$build/.klab-commit" ]] && commit="$(cat "$build/.klab-commit")"
      if [[ -z "$commit" && -d "$SRC/.git" ]]; then
        # Best effort: current source commit. This is exact only when the current
        # checkout still corresponds to the cached mainline build.
        commit="$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)"
      fi
      [[ -n "$commit" ]] || die "cannot determine mainline commit; rebuild it with current kernel-lab before exporting"
      printf '%s\n' "$commit"
      ;;
    v*) printf '%s\n' "$1" ;;
    *) printf 'v%s\n' "$1" ;;
  esac
}

write_manifest() {
  local out="$1" kind="$2" target="$3" profile="$4" provider="$5" release="$6" krel="$7" \
        build_image="$8" upstream_ref="$9"
  shift 9
  local payload_json="$1" toolchain_json="$2" image_json="$3" guest_json="${4:-}"
  local arch_plan
  arch_plan="$(klab_arch_plan_json "$ARCH" "$(klab_arch_host)")"
  FORMAT_NAME="$FORMAT_NAME" FORMAT_VERSION="$FORMAT_VERSION" ARCH="$ARCH" ARCH_PLAN="$arch_plan" \
  KIND="$kind" TARGET="$target" PROFILE="$profile" PROVIDER="$provider" \
  RELEASE="$release" KREL="$krel" BUILD_IMAGE="$build_image" UREF="$upstream_ref" \
  PAYLOAD_JSON="$payload_json" TOOLCHAIN_JSON="$toolchain_json" IMAGE_JSON="$image_json" GUEST_JSON="$guest_json" \
  python3 - "$out" <<'PY'
import json,os,sys,datetime
out=sys.argv[1]
def maybe_json(name, default=None):
    v=os.environ.get(name,'')
    return json.loads(v) if v else default
m={
  "format": os.environ["FORMAT_NAME"],
  "format_version": int(os.environ["FORMAT_VERSION"]),
  "created_at": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z'),
  "arch": os.environ["ARCH"],
  "architecture_model": maybe_json("ARCH_PLAN"),
  "kind": os.environ["KIND"],
  "target": os.environ["TARGET"],
  "profile": os.environ.get("PROFILE") or None,
  "provider": os.environ.get("PROVIDER") or None,
  "release": os.environ.get("RELEASE") or None,
  "kernel_release": os.environ.get("KREL") or None,
  "build_image": os.environ.get("BUILD_IMAGE") or None,
  "upstream_ref": os.environ.get("UREF") or None,
  "payloads": maybe_json("PAYLOAD_JSON", []),
  "toolchain": maybe_json("TOOLCHAIN_JSON"),
  "container_image": maybe_json("IMAGE_JSON"),
  "guest_userspace": maybe_json("GUEST_JSON"),
}
with open(out,'w',encoding='utf-8') as f:
    json.dump(m,f,indent=2,sort_keys=True); f.write('\n')
PY
}

add_checksum_line() {
  local stage="$1" rel="$2"
  (cd "$stage" && sha256sum "$rel") >> "$stage/SHA256SUMS"
}

cmd_create_legacy() {
  need_common
  (($# >= 1)) || { usage; exit 2; }
  local target="$1"; shift
  local output="" profile="normal" toolchain="" toolchain_id="" toolchain_cc="" image="" auto_toolchain=0 userspace="busybox-static" include_sdk=0
  while (($#)); do
    case "$1" in
      -o|--output) [[ $# -ge 2 ]] || die "$1 needs a value"; output="$2"; shift 2 ;;
      --profile) [[ $# -ge 2 ]] || die "$1 needs a value"; profile="$2"; shift 2 ;;
      --include-toolchain) [[ $# -ge 2 ]] || die "$1 needs a value"; toolchain="$2"; shift 2 ;;
      --auto-toolchain) auto_toolchain=1; shift ;;
      --toolchain-id) [[ $# -ge 2 ]] || die "$1 needs a value"; toolchain_id="$2"; shift 2 ;;
      --toolchain-cc) [[ $# -ge 2 ]] || die "$1 needs a value"; toolchain_cc="$2"; shift 2 ;;
      --include-image) [[ $# -ge 2 ]] || die "$1 needs a value"; image="$2"; shift 2 ;;
      --userspace) [[ $# -ge 2 ]] || die "$1 needs a value"; userspace="$2"; shift 2 ;;
      --include-sdk) include_sdk=1; shift ;;
      *) die "unknown create option '$1'" ;;
    esac
  done

  parse_target "$target"
  userspace="$(normalize_userspace_spec "$userspace")"
  if (( include_sdk == 1 )) && [[ "$userspace" != buildroot:* ]]; then
    die "--include-sdk requires --userspace buildroot:minimal or buildroot:network"
  fi
  if (( auto_toolchain == 1 )) && [[ -n "$toolchain" ]]; then
    die "--auto-toolchain and --include-toolchain are mutually exclusive"
  fi
  local safe stage kind provider release krel build_image="" upstream_ref=""
  safe="$(safe_name "$target")"
  if [[ -z "$output" ]]; then
    if [[ "$PROVIDER" == upstream ]]; then output="$PWD/${safe}__${profile}.klab"; else output="$PWD/${safe}.klab"; fi
  fi
  [[ "$output" == *.klab ]] || output="$output.klab"
  output="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$output")"
  stage="$(mktemp -d)"
  trap "rm -rf '$stage'" EXIT
  mkdir -p "$stage/payload" "$stage/extras"
  printf '%s\n' "$FORMAT_VERSION" > "$stage/FORMAT_VERSION"

  local payload_json toolchain_json="" image_json="" guest_json=""

  if [[ "$PROVIDER" == upstream ]]; then
    [[ -z "$KERNEL_RELEASE" ]] || die "upstream target syntax is upstream:v6.6, not three fields"
    kind="upstream"
    provider="upstream"; release="$DISTRO_RELEASE"; krel=""
    local build ref src_payload build_payload build_sha src_sha actual_krel commit source_dir=""
    build="$(find_upstream_build "$release" "$profile" "$ARCH")"
    ref="$(upstream_ref_for "$release" "$build")"
    if [[ -f "$build/.klab-commit" ]]; then
      commit="$(cat "$build/.klab-commit")"
    elif [[ -d "$SRC/.git" ]]; then
      git -C "$SRC" cat-file -e "$ref^{commit}" 2>/dev/null || die "upstream ref '$ref' is not present in $SRC; fetch/build it before export"
      commit="$(git -C "$SRC" rev-parse "$ref^{commit}")"
    else
      die "cannot determine upstream source commit for $release/$profile"
    fi
    upstream_ref="$commit"
    actual_krel="$(cat "$build/include/config/kernel.release" 2>/dev/null || true)"
    krel="$actual_krel"
    if [[ -f "$build/.klab-source-dir" ]]; then
      source_dir="$(cat "$build/.klab-source-dir")"
      [[ -d "$source_dir" && -f "$source_dir/Makefile" ]] || die "cached build references missing immutable source tree: $source_dir"
    fi

    src_payload="$stage/payload/source.tar.zst"
    if [[ -n "$source_dir" ]]; then
      say "Packing immutable upstream source tree $(basename "$source_dir")"
      tar -C "$source_dir" --zstd -cf "$src_payload" .
    else
      [[ -d "$SRC/.git" ]] || die "legacy build has no immutable source tree and source repository is unavailable"
      git -C "$SRC" cat-file -e "$commit^{commit}" 2>/dev/null || die "upstream commit '$commit' is not present in $SRC"
      say "Packing legacy upstream source snapshot $commit"
      git -C "$SRC" archive --format=tar "$commit" | zstd -T0 -q -3 -o "$src_payload"
    fi
    src_sha="$(sha256_file "$src_payload")"

    say "Packing upstream build tree $(basename "$build")"
    build_payload="$stage/payload/build.tar.zst"
    tar -C "$build" --zstd -cf "$build_payload" .
    build_sha="$(sha256_file "$build_payload")"

    payload_json="$(python3 - "$src_sha" "$build_sha" "$ref" "$(basename "$build")" <<'PY'
import json,sys
s,b,ref,key=sys.argv[1:]
print(json.dumps([
 {"role":"upstream-source","path":"payload/source.tar.zst","sha256":s,"ref":ref},
 {"role":"upstream-build","path":"payload/build.tar.zst","sha256":b,"build_key":key}
]))
PY
)"
    add_checksum_line "$stage" payload/source.tar.zst
    add_checksum_line "$stage" payload/build.tar.zst
  else
    [[ -n "$KERNEL_RELEASE" ]] || die "distro target needs provider:release:kernel-release"
    kind="distro"; provider="$PROVIDER"; release="$DISTRO_RELEASE"; krel="$KERNEL_RELEASE"
    local bundle payload psha rel_build="" rel_source="" rel_modules=""
    bundle="$(bundle_existing_dir_for "$provider" "$release" "$krel" "$ARCH")"
    [[ -f "$bundle/bundle.env" ]] || die "distro target is not cached: $target; run kernel-lab.sh fetch '$target' first"
    # shellcheck disable=SC1090
    source "$bundle/bundle.env"
    build_image="${BUNDLE_BUILD_IMAGE:-}"
    [[ -n "${BUNDLE_BUILD_DIR:-}" && "$BUNDLE_BUILD_DIR" == "$bundle"/* ]] && rel_build="${BUNDLE_BUILD_DIR#"$bundle"/}"
    [[ -n "${BUNDLE_SOURCE_DIR:-}" && "$BUNDLE_SOURCE_DIR" == "$bundle"/* ]] && rel_source="${BUNDLE_SOURCE_DIR#"$bundle"/}"
    [[ -n "${BUNDLE_MODULES_DIR:-}" && "$BUNDLE_MODULES_DIR" == "$bundle"/* ]] && rel_modules="${BUNDLE_MODULES_DIR#"$bundle"/}"

    say "Packing cached distro bundle $target"
    payload="$stage/payload/distro-bundle.tar.zst"
    tar -C "$bundle" --zstd -cf "$payload" .
    psha="$(sha256_file "$payload")"
    payload_json="$(python3 - "$psha" "$rel_build" "$rel_source" "$rel_modules" <<'PY'
import json,sys
sha,b,s,m=sys.argv[1:]
print(json.dumps([{"role":"distro-bundle","path":"payload/distro-bundle.tar.zst","sha256":sha,
                   "build_dir_rel":b or None,"source_dir_rel":s or None,"modules_dir_rel":m or None}]))
PY
)"
    add_checksum_line "$stage" payload/distro-bundle.tar.zst
  fi

  if (( auto_toolchain == 1 )); then
    [[ -f "$KERNEL_LAB_BIN" || -x "$KERNEL_LAB_BIN" ]] || die "kernel-lab tool not found: $KERNEL_LAB_BIN (set KLAB_KERNEL_LAB_BIN)"
    say "Resolving and caching toolchain automatically for $target"
    toolchain="$(KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" KLAB_ARCH="$ARCH" "$KERNEL_LAB_BIN" toolchain ensure "$target" "$profile")"
    [[ -d "$toolchain" ]] || die "automatic toolchain resolver returned an invalid directory: $toolchain"
    if [[ -z "$toolchain_id" && -f "$toolchain/.klab-resolver.env" ]]; then
      unset KLAB_TOOLCHAIN_ID
      # shellcheck disable=SC1090
      source "$toolchain/.klab-resolver.env"
      toolchain_id="${KLAB_TOOLCHAIN_ID:-}"
    fi
  fi

  if [[ -n "$toolchain" ]]; then
    toolchain="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$toolchain")"
    [[ -d "$toolchain" ]] || die "toolchain directory not found: $toolchain"
    say "Packing toolchain $(basename "$toolchain")"
    local tc_cc_abs tc_cc_rel tc_boundary_json tsha
    tc_cc_abs="$(detect_toolchain_cc "$toolchain" "$toolchain_cc")"
    tc_cc_rel="${tc_cc_abs#"$toolchain"/}"
    tc_boundary_json="$("$TOOLCHAIN_BOUNDARY_BIN" seal --root "$toolchain" --cc "$tc_cc_rel" --json)"
    tar -C "$toolchain" --zstd -cf "$stage/extras/toolchain.tar.zst" .
    tsha="$(sha256_file "$stage/extras/toolchain.tar.zst")"
    toolchain_json="$(probe_toolchain_json "$toolchain" "$tsha" "$toolchain_id" "$toolchain_cc")"
    toolchain_json="$(python3 - "$toolchain_json" "$tc_boundary_json" <<'PY_TC_BOUNDARY_MERGE'
import json,sys
t,b=map(json.loads,sys.argv[1:])
t['tree_sha256']=b['tree_sha256']
t['boundary_format']=b['format']
t['boundary_version']=b['format_version']
t['programs']=b['programs']
print(json.dumps(t,separators=(',',':')))
PY_TC_BOUNDARY_MERGE
    )"
    add_checksum_line "$stage" extras/toolchain.tar.zst
  fi

  # Linux test guests carry an explicit guest-userspace payload. Kernel Lab
  # still injects /init, modules, tests, and the control protocol at run time.
  if [[ "$kind" == upstream || "$kind" == distro ]]; then
    case "$userspace" in
      busybox-static)
        local guest_bb guest_sha
        guest_bb="${KLAB_GUEST_BUSYBOX_OVERRIDE:-$(guest_busybox_path "$ARCH")}"
        [[ -x "$guest_bb" ]] || die "guest BusyBox for $ARCH is missing: $guest_bb; run kernel-lab.sh prepare so it can be acquired on the staging machine"
        cp "$guest_bb" "$stage/extras/guest-busybox"
        chmod 0755 "$stage/extras/guest-busybox"
        guest_sha="$(sha256_file "$stage/extras/guest-busybox")"
        guest_json="$(python3 - "$ARCH" "$guest_sha" <<'PY_GUEST'
import json,sys
print(json.dumps({"kind":"busybox-static","spec":"busybox-static","arch":sys.argv[1],"path":"extras/guest-busybox","sha256":sys.argv[2]}))
PY_GUEST
)"
        add_checksum_line "$stage" extras/guest-busybox
        ;;
      buildroot:minimal|buildroot:network|buildroot:ssh)
        local brprofile guest_rootfs guest_meta guest_sha brver brdef brcfgsha brsrcsha guest_cfg guest_frag cfg_payload_sha frag_payload_sha
        local guest_sdk="" guest_sdk_sha="" sdk_json_fragment=""
        brprofile="${userspace#buildroot:}"
        guest_rootfs="$(buildroot_rootfs_path "$ARCH" "$brprofile")"; guest_meta="$(buildroot_guest_metadata_path "$ARCH" "$brprofile")"
        guest_cfg="$(dirname "$guest_rootfs")/buildroot.config"; guest_frag="$(dirname "$guest_rootfs")/busybox.fragment"
        [[ -f "$guest_rootfs" && -f "$guest_meta" && -f "$guest_cfg" && -f "$guest_frag" ]] || die "Buildroot $brprofile userspace for $ARCH is incomplete; run kernel-lab.sh prepare ... --userspace buildroot:$brprofile first"
        unset KLAB_BUILDROOT_VERSION KLAB_BUILDROOT_DEFCONFIG KLAB_BUILDROOT_CONFIG_SHA256 KLAB_BUILDROOT_SOURCE_SHA256 KLAB_BUILDROOT_SDK_SHA256
        # shellcheck disable=SC1090
        source "$guest_meta"
        brver="${KLAB_BUILDROOT_VERSION:-$BUILDROOT_VERSION}"; brdef="${KLAB_BUILDROOT_DEFCONFIG:-unknown}"; brcfgsha="${KLAB_BUILDROOT_CONFIG_SHA256:-}"; brsrcsha="${KLAB_BUILDROOT_SOURCE_SHA256:-}"
        cp "$guest_rootfs" "$stage/extras/guest-rootfs.tar"
        cp "$guest_cfg" "$stage/extras/buildroot.config"
        cp "$guest_frag" "$stage/extras/busybox.fragment"
        guest_sha="$(sha256_file "$stage/extras/guest-rootfs.tar")"
        cfg_payload_sha="$(sha256_file "$stage/extras/buildroot.config")"; frag_payload_sha="$(sha256_file "$stage/extras/busybox.fragment")"
        if (( include_sdk == 1 )); then
          guest_sdk="$(buildroot_sdk_archive_path "$ARCH" "$brprofile")"
          [[ -f "$guest_sdk" ]] || die "Buildroot SDK $brprofile/$ARCH is missing; run kernel-lab.sh prepare ... --with-sdk first"
          cp "$guest_sdk" "$stage/extras/buildroot-sdk.tar.gz"
          guest_sdk_sha="$(sha256_file "$stage/extras/buildroot-sdk.tar.gz")"
          add_checksum_line "$stage" extras/buildroot-sdk.tar.gz
        fi
        guest_json="$(python3 - "$ARCH" "$guest_sha" "$brver" "$brdef" "$brcfgsha" "$brsrcsha" "$cfg_payload_sha" "$frag_payload_sha" "$brprofile" "$guest_sdk_sha" <<'PY_GUEST_BR'
import json,sys
arch,sha,ver,defcfg,cfgsha,srcsha,cfgpayload,fragpayload,profile,sdksha=sys.argv[1:]
o={"kind":"buildroot-"+profile,"spec":"buildroot:"+profile,"arch":arch,"path":"extras/guest-rootfs.tar","sha256":sha,"buildroot_version":ver,"profile":profile,"defconfig":defcfg,"config_sha256":cfgsha or None,"source_sha256":srcsha or None,"config_path":"extras/buildroot.config","config_payload_sha256":cfgpayload,"busybox_fragment_path":"extras/busybox.fragment","busybox_fragment_sha256":fragpayload}
if sdksha:
    o["sdk"]={"path":"extras/buildroot-sdk.tar.gz","sha256":sdksha,"format":"buildroot-sdk-tar.gz"}
print(json.dumps(o))
PY_GUEST_BR
)"
        add_checksum_line "$stage" extras/guest-rootfs.tar
        add_checksum_line "$stage" extras/buildroot.config
        add_checksum_line "$stage" extras/busybox.fragment
        ;;
      native:*)
        local native_provider native_release native_rootfs native_meta native_sha native_meta_sha
        IFS=: read -r _native_kind native_provider native_release <<<"$userspace"
        [[ -n "$native_provider" && -n "$native_release" ]] || die "invalid native userspace selector '$userspace'"
        native_rootfs="$(native_rootfs_path "$native_provider" "$native_release" "$ARCH")"
        native_meta="$(native_metadata_path "$native_provider" "$native_release" "$ARCH")"
        [[ -f "$native_rootfs" && -f "$native_meta" ]] || die "native userspace $native_provider:$native_release/$ARCH is incomplete; capture it before bundling"
        cp "$native_rootfs" "$stage/extras/native-rootfs.tar.zst"
        cp "$native_meta" "$stage/extras/native-metadata.env"
        native_sha="$(sha256_file "$stage/extras/native-rootfs.tar.zst")"
        native_meta_sha="$(sha256_file "$stage/extras/native-metadata.env")"
        guest_json="$(python3 - "$ARCH" "$native_sha" "$native_meta_sha" "$native_provider" "$native_release" <<'PY_GUEST_NATIVE'
import json,sys
arch,sha,meta_sha,provider,release=sys.argv[1:]
print(json.dumps({"kind":"native","spec":f"native:{provider}:{release}","arch":arch,"provider":provider,"release":release,"path":"extras/native-rootfs.tar.zst","sha256":sha,"metadata_path":"extras/native-metadata.env","metadata_sha256":meta_sha}))
PY_GUEST_NATIVE
)"
        add_checksum_line "$stage" extras/native-rootfs.tar.zst
        add_checksum_line "$stage" extras/native-metadata.env
        ;;
    esac
  fi

  if [[ -n "$image" ]]; then
    local rt isha
    rt="$(container_runtime)"
    say "Saving container image $image using $rt"
    "$rt" image inspect "$image" >/dev/null 2>&1 || die "container image not present locally: $image"
    "$rt" save "$image" | zstd -T0 -q -3 -o "$stage/extras/container-image.tar.zst"
    isha="$(sha256_file "$stage/extras/container-image.tar.zst")"
    image_json="$(python3 - "$isha" "$image" <<'PY'
import json,sys
print(json.dumps({"path":"extras/container-image.tar.zst","sha256":sys.argv[1],"name":sys.argv[2]}))
PY
)"
    add_checksum_line "$stage" extras/container-image.tar.zst
  fi

  local manifest_profile="$profile"
  [[ "$kind" == upstream ]] || manifest_profile=""
  write_manifest "$stage/manifest.json" "$kind" "$target" "$manifest_profile" "$provider" "$release" "$krel" "$build_image" "$upstream_ref" "$payload_json" "$toolchain_json" "$image_json" "$guest_json"
  # KLAB_BUILDENV_TRANSFER_M2: thin target references the shared buildenv by content ID.
  if [[ -n "${BUNDLE_BUILDENV_ID:-}" ]]; then
    local __be_provider __be_release __be_krel __be_arch __be_json
    __be_provider="$(json_get "$stage/manifest.json" provider)"
    __be_release="$(json_get "$stage/manifest.json" release)"
    __be_krel="$(json_get "$stage/manifest.json" kernel_release)"
    __be_arch="$(json_get "$stage/manifest.json" arch)"
    __be_json="$(KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" assert-installed "$BUNDLE_BUILDENV_ID" \
      --provider "$__be_provider" --release "$__be_release" --kernel-release "$__be_krel" --target-arch "$__be_arch" --json)"
    python3 - "$stage/manifest.json" "$BUNDLE_BUILDENV_ID" "$__be_json" <<'PY_BUILDENV_REF'
import json,sys
p,i,b=sys.argv[1:]
m=json.load(open(p)); be=json.loads(b)
m['buildenv']={
  'type':'buildenv','id':i,'extension':'.klabbuildenv',
  'provider':be.get('provider'),'release':be.get('release'),
  'kernel_release':be.get('kernel_release'),'target_arch':be.get('target_arch'),
  'exec_arch':be.get('exec_arch'),'root_tree_sha256':be.get('root_tree_sha256'),
  'toolchain_tree_sha256':be.get('toolchain_tree_sha256') or None,
  'compiler_contract':be.get('compiler_contract') or 'gcc-v1',
  'distro_toolchain_id':be.get('distro_toolchain_id') or None,
}
with open(p,'w') as f: json.dump(m,f,indent=2,sort_keys=True); f.write('\n')
PY_BUILDENV_REF
  fi
  add_checksum_line "$stage" manifest.json
  sort -k2 -o "$stage/SHA256SUMS" "$stage/SHA256SUMS"

  mkdir -p "$(dirname "$output")"
  say "Creating $output"
  tar -C "$stage" --zstd -cf "$output" FORMAT_VERSION manifest.json SHA256SUMS payload extras
  printf '%s  %s\n' "$(sha256_file "$output")" "$output"
}

extract_outer() {
  local file="$1" dir="$2"
  [[ -f "$file" ]] || die "bundle not found: $file"
  mkdir -p "$dir"
  tar --zstd -xf "$file" -C "$dir"
}

verify_stage() {
  local stage="$1"
  [[ -f "$stage/FORMAT_VERSION" && -f "$stage/manifest.json" && -f "$stage/SHA256SUMS" ]] || die "not a valid .klab archive: required metadata missing"
  [[ "$(cat "$stage/FORMAT_VERSION")" == "$FORMAT_VERSION" ]] || die "unsupported .klab format version $(cat "$stage/FORMAT_VERSION")"
  [[ "$(json_get "$stage/manifest.json" format)" == "$FORMAT_NAME" ]] || die "manifest format is not $FORMAT_NAME"
  [[ "$(json_get "$stage/manifest.json" format_version)" == "$FORMAT_VERSION" ]] || die "manifest format version mismatch"
  local __am_target __am_arch
  __am_target="$(json_get "$stage/manifest.json" architecture_model.target_arch 2>/dev/null || true)"
  if [[ -n "$__am_target" ]]; then
    __am_arch="$(canonical_arch "$(json_get "$stage/manifest.json" arch)")"
    [[ "$(canonical_arch "$__am_target")" == "$__am_arch" ]] || die "architecture model target does not match bundle arch"
  fi
  (cd "$stage" && sha256sum -c SHA256SUMS)
}

cmd_verify() {
  need_common
  [[ $# -eq 1 ]] || { usage; exit 2; }
  local tmp; tmp="$(mktemp -d)"; trap "rm -rf '$tmp'" EXIT
  extract_outer "$1" "$tmp"
  verify_stage "$tmp"
  say "Verified: $1"
}

cmd_inspect() {
  need_common
  [[ $# -eq 1 ]] || { usage; exit 2; }
  local tmp; tmp="$(mktemp -d)"; trap "rm -rf '$tmp'" EXIT
  extract_outer "$1" "$tmp"
  verify_stage "$tmp" >/dev/null
  python3 - "$tmp/manifest.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
print(f"Format:          {m['format']} v{m['format_version']}")
print(f"Created:         {m['created_at']}")
print(f"Kind:            {m['kind']}")
print(f"Target:          {m['target']}")
print(f"Architecture:    {m['arch']}")
am=m.get('architecture_model') or {}
if am:
    print(f"Build arch:      {am.get('build_arch','?')}")
    print(f"Cross compile:   {'yes' if am.get('cross_compile') else 'no'}")
    p=am.get('profile') or {}
    print(f"Arch profile:    {p.get('family','?')} / {p.get('bits','?')}-bit / {p.get('endian','?')} / {p.get('abi','?')}")
if m.get('backend'): print(f"Backend:         {m['backend']}")
if m.get('capabilities'): print(f"Capabilities:    {','.join(m['capabilities']) if isinstance(m['capabilities'],list) else m['capabilities']}")
if m.get('profile'): print(f"Profile:         {m['profile']}")
if m.get('kernel_release'): print(f"Kernel release:  {m['kernel_release']}")
if m.get('upstream_ref'): print(f"Upstream commit: {m['upstream_ref']}")
if m.get('build_image'): print(f"Build image:     {m['build_image']}")
print("Payloads:")
for p in m.get('payloads',[]): print(f"  {p['role']}: {p['path']}  sha256={p['sha256'][:16]}...")
if m.get('toolchain'):
    t=m['toolchain']
    print(f"Toolchain:       {t.get('id',t.get('name'))}")
    if t.get('family'): print(f"  compiler:      {t['family']} {t.get('version','?')}")
    if t.get('target'): print(f"  target:        {t['target']}")
    if t.get('cc_relpath'): print(f"  compiler path: {t['cc_relpath']}")
    if t.get('resolver_source'): print(f"  source:        {t['resolver_source']}")
    if t.get('requested_version') and t.get('requested_version') != t.get('version'):
        print(f"  target wanted: GCC {t['requested_version']} (same-major fallback selected)")
    tc=t.get('target_compiler') or {}
    if tc.get('version'): print(f"  kernel built:  {tc.get('family','?')} {tc['version']}")
    print(f"  bound:         {bool(t.get('bound'))}")
if m.get('guest_userspace'):
    g=m['guest_userspace']; print(f"Guest userspace: {g.get('spec') or g.get('kind')} ({g.get('arch')})")
    if g.get('buildroot_version'): print(f"  Buildroot:      {g.get('buildroot_version')} / {g.get('profile','minimal')} / {g.get('defconfig','?')}")
    if g.get('sdk'): print(f"  SDK:            included ({g['sdk'].get('format','archive')}) sha256={g['sdk'].get('sha256','')[:16]}...")
if m.get('container_image'): print(f"Container image: {m['container_image']['name']}")
PY
}

quote_env() { printf '%q' "$1"; }

fixup_distro_env() {
  local dest="$1" manifest="$2" installed_dest="${3:-$1}"
  local provider release krel arch build_image build_rel source_rel modules_rel
  local build source modules build_stage source_stage modules_stage
  provider="$(json_get "$manifest" provider)"
  release="$(json_get "$manifest" release)"
  krel="$(json_get "$manifest" kernel_release)"
  arch="$(canonical_arch "$(json_get "$manifest" arch)")"
  build_image="$(json_get "$manifest" build_image)"
  build_rel="$(json_get "$manifest" payloads.0.build_dir_rel)"
  source_rel="$(json_get "$manifest" payloads.0.source_dir_rel 2>/dev/null || true)"
  modules_rel="$(json_get "$manifest" payloads.0.modules_dir_rel)"

  build_stage="${build_rel:+$dest/$build_rel}"
  source_stage="${source_rel:+$dest/$source_rel}"
  modules_stage="${modules_rel:+$dest/$modules_rel}"
  if [[ -z "$build_stage" || ! -d "$build_stage" ]]; then
    local candidate rel
    for candidate in "$dest/root/usr/src/linux-headers-$krel" "$dest/root/usr/src/kernels/$krel"; do
      if [[ -d "$candidate" ]]; then
        build_stage="$candidate"
        rel="${candidate#"$dest"/}"
        build_rel="$rel"
        break
      fi
    done
  fi
  [[ -n "$build_stage" && -d "$build_stage" ]] || die "imported bundle has no usable module build tree for $krel"
  [[ -z "$source_stage" || -d "$source_stage" ]] || source_rel=""
  [[ -z "$modules_stage" || -d "$modules_stage" ]] || modules_rel=""

  build="$installed_dest/$build_rel"
  source="${source_rel:+$installed_dest/$source_rel}"
  modules="${modules_rel:+$installed_dest/$modules_rel}"

  local buildenv_id="" buildenv_dir="" distro_toolchain_id="" distro_toolchain_dir=""
  buildenv_id="$(json_get "$manifest" buildenv.id 2>/dev/null || true)"
  if [[ -n "$buildenv_id" ]]; then
    buildenv_dir="$KLAB_BUILDENV_STORE/sha256/$buildenv_id"
    distro_toolchain_id="$(json_get "$manifest" buildenv.distro_toolchain_id 2>/dev/null || true)"
    if [[ -n "$distro_toolchain_id" && "$distro_toolchain_id" != null ]]; then
      distro_toolchain_dir="$(KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "${KLAB_DISTRO_TOOLCHAIN_BIN:-$SELF_DIR/klab-distro-toolchain.sh}" assert-installed "$distro_toolchain_id" --provider "$provider" --release "$release" --arch "$arch")"
    else distro_toolchain_id=""; fi
    KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" assert-installed "$buildenv_id" \
      --provider "$provider" --release "$release" --kernel-release "$krel" --target-arch "$arch" --exec-arch "$(uname -m)" >/dev/null
  fi

  {
    [[ -z "$buildenv_id" ]] || {
      printf 'BUNDLE_BUILDENV_ID=%q\n' "$buildenv_id"
      printf 'BUNDLE_BUILDENV_DIR=%q\n' "$buildenv_dir"
      [[ -z "$distro_toolchain_id" ]] || { printf 'BUNDLE_DISTRO_TOOLCHAIN_ID=%q\n' "$distro_toolchain_id"; printf 'BUNDLE_DISTRO_TOOLCHAIN_DIR=%q\n' "$distro_toolchain_dir"; }
    }
    printf 'BUNDLE_PROVIDER=%q\n' "$provider"
    printf 'BUNDLE_DISTRO_RELEASE=%q\n' "$release"
    printf 'BUNDLE_KERNEL_RELEASE=%q\n' "$krel"
    printf 'BUNDLE_TARGET_ID=%q\n' "$provider:$release:$krel"
    printf 'BUNDLE_BACKEND=linux\n'
    printf 'BUNDLE_CAPABILITIES=%q\n' 'boot,push,exec,module-build,module-load,module-unload,module-list,crash-console,crash-vmcore'
    printf 'BUNDLE_ARCH=%q\n' "$arch"
    printf 'BUNDLE_DIR=%q\n' "$installed_dest"
    printf 'BUNDLE_PACKAGES=%q\n' "$installed_dest/packages"
    printf 'BUNDLE_ROOT=%q\n' "$installed_dest/root"
    printf 'BUNDLE_KERNEL_IMAGE=%q\n' "$installed_dest/vmlinuz"
    printf 'BUNDLE_BUILD_DIR=%q\n' "$build"
    printf 'BUNDLE_SOURCE_DIR=%q\n' "$source"
    printf 'BUNDLE_MODULES_DIR=%q\n' "$modules"
    printf 'BUNDLE_BUILD_IMAGE=%q\n' "$build_image"
    printf 'BUNDLE_FETCHED_AT=%q\n' "$(json_get "$manifest" created_at)"
    printf 'BUNDLE_IMPORTED_FROM_KLAB=1\n'
  } > "$dest/bundle.env"
}

cmd_import_legacy() {
  need_common
  (($# >= 1)) || { usage; exit 2; }
  local file="$1"; shift
  local force=0 load_image=0
  while (($#)); do
    case "$1" in
      --force) force=1 ;;
      --load-image) load_image=1 ;;
      *) die "unknown import option '$1'" ;;
    esac
    shift
  done

  local tmp; tmp="$(mktemp -d)"
  local __atomic_final="" __atomic_tmp="" __atomic_old=""
  # KLAB_ATOMIC_TARGET_IMPORT_M2: partial imports live beside the final target
  # and are discarded on failure; the installed target is untouched until commit.
  trap "remove_tree '$tmp'; [[ -z \"\${__atomic_tmp:-}\" ]] || remove_tree \"\${__atomic_tmp}\"" EXIT
  extract_outer "$file" "$tmp"
  verify_stage "$tmp"

  # KLAB_BUILDENV_TRANSFER_M2: preflight thin buildenv dependencies before
  # touching an existing target installation. This makes failed imports
  # non-destructive and rejects valid-but-wrong buildenv references.
  local __be_pre_id="" __be_pre_provider="" __be_pre_release="" __be_pre_krel="" __be_pre_arch="" __be_pre_tc=""
  __be_pre_id="$(json_get "$tmp/manifest.json" buildenv.id 2>/dev/null || true)"
  if [[ -n "$__be_pre_id" ]]; then
    __be_pre_provider="$(json_get "$tmp/manifest.json" provider)"
    __be_pre_release="$(json_get "$tmp/manifest.json" release)"
    __be_pre_krel="$(json_get "$tmp/manifest.json" kernel_release)"
    __be_pre_arch="$(json_get "$tmp/manifest.json" arch)"
    __be_pre_tc="$(json_get "$tmp/manifest.json" buildenv.toolchain_tree_sha256 2>/dev/null || true)"
    local __be_assert=(assert-installed "$__be_pre_id" --provider "$__be_pre_provider" --release "$__be_pre_release" --kernel-release "$__be_pre_krel" --target-arch "$__be_pre_arch" --exec-arch "$(uname -m)")
    [[ -n "$__be_pre_tc" ]] && __be_assert+=(--toolchain-tree-sha256 "$__be_pre_tc")
    KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" "${__be_assert[@]}" >/dev/null
  fi


  local kind target provider release krel profile arch dest
  kind="$(json_get "$tmp/manifest.json" kind)"
  target="$(json_get "$tmp/manifest.json" target)"
  provider="$(json_get "$tmp/manifest.json" provider)"
  release="$(json_get "$tmp/manifest.json" release)"
  krel="$(json_get "$tmp/manifest.json" kernel_release)"
  profile="$(json_get "$tmp/manifest.json" profile)"
  arch="$(canonical_arch "$(json_get "$tmp/manifest.json" arch)")"

  mkdir -p "$KERNELS" "$TOOLCHAINS" "$KLAB_RESULTS/logs" "$KLAB_WORK/jobs" "$KLAB_WORK/initramfs"
  if [[ "$kind" == distro ]]; then
    dest="$(bundle_dir_for "$provider" "$release" "$krel" "$arch")"
    __atomic_final="$dest"
    if [[ -e "$__atomic_final" ]]; then
      (( force == 1 )) || die "destination already exists: $__atomic_final (use --force to replace)"
    fi
    __atomic_tmp="${__atomic_final}.klab-import.$$"
    trap "remove_tree '$tmp'; remove_tree '$__atomic_tmp'" EXIT
    remove_tree "$__atomic_tmp"
    dest="$__atomic_tmp"
    mkdir -p "$dest"
    say "Importing $target to $dest"
    tar --zstd -xf "$tmp/payload/distro-bundle.tar.zst" -C "$dest"
    fixup_distro_env "$dest" "$tmp/manifest.json" "$__atomic_final"
  elif [[ "$kind" == upstream ]]; then
    local ver="${release#v}"
    [[ "$release" == mainline || "$release" == master ]] && ver=mainline
    dest="$KERNELS/upstream/$ver/$arch/$profile"
    __atomic_final="$dest"
    if [[ -e "$__atomic_final" ]]; then
      (( force == 1 )) || die "destination already exists: $__atomic_final (use --force to replace)"
    fi
    __atomic_tmp="${__atomic_final}.klab-import.$$"
    trap "remove_tree '$tmp'; remove_tree '$__atomic_tmp'" EXIT
    remove_tree "$__atomic_tmp"
    dest="$__atomic_tmp"
    mkdir -p "$dest/source" "$dest/build"
    say "Importing $target/$profile to $dest"
    tar --zstd -xf "$tmp/payload/source.tar.zst" -C "$dest/source"
    tar --zstd -xf "$tmp/payload/build.tar.zst" -C "$dest/build"
    local installed_dest="$__atomic_final" kernel_image_rel
    printf '%s\n' "$installed_dest/source" > "$dest/build/.klab-source-dir"
    kernel_image_rel="$(cat "$dest/build/.klab-image-rel" 2>/dev/null || linux_kernel_image_rel "$arch")"
    case "$kernel_image_rel" in
      /*|../*|*/../*|*/..) die "upstream bundle contains unsafe kernel image path: $kernel_image_rel" ;;
    esac
    [[ -f "$dest/build/$kernel_image_rel" ]] || die "upstream bundle kernel image is missing: $kernel_image_rel"
    cat > "$dest/bundle.env" <<EOFENV
BUNDLE_PROVIDER=upstream
BUNDLE_UPSTREAM_VERSION=$(quote_env "$release")
BUNDLE_PROFILE=$(quote_env "$profile")
BUNDLE_ARCH=$(quote_env "$arch")
BUNDLE_KERNEL_RELEASE=$(quote_env "$krel")
BUNDLE_DIR=$(quote_env "$installed_dest")
BUNDLE_SOURCE_DIR=$(quote_env "$installed_dest/source")
BUNDLE_BUILD_DIR=$(quote_env "$installed_dest/build")
BUNDLE_KERNEL_IMAGE=$(quote_env "$installed_dest/build/$kernel_image_rel")
BUNDLE_UPSTREAM_REF=$(quote_env "$(json_get "$tmp/manifest.json" upstream_ref)")
BUNDLE_IMPORTED_FROM_KLAB=1
EOFENV
  else
    die "unsupported bundle kind '$kind'"
  fi

  local guest_kind="" guest_arch="" guest_sha="" guest_spec=""
  guest_kind="$(json_get "$tmp/manifest.json" guest_userspace.kind 2>/dev/null || true)"
  guest_spec="$(json_get "$tmp/manifest.json" guest_userspace.spec 2>/dev/null || true)"
  if [[ -n "$guest_kind" ]]; then
    guest_arch="$(canonical_arch "$(json_get "$tmp/manifest.json" guest_userspace.arch)")"
    [[ "$guest_arch" == "$arch" ]] || die "guest userspace architecture $guest_arch does not match bundle architecture $arch"
    guest_sha="$(json_get "$tmp/manifest.json" guest_userspace.sha256)"
    case "$guest_kind" in
      busybox-static)
        local guest_dest guest_have
        [[ -f "$tmp/extras/guest-busybox" ]] || die "bundle manifest declares BusyBox userspace but payload is missing"
        [[ "$(sha256_file "$tmp/extras/guest-busybox")" == "$guest_sha" ]] || die "guest BusyBox checksum mismatch"
        guest_dest="$(guest_busybox_path "$guest_arch")"
        mkdir -p "$(dirname "$guest_dest")"
        if [[ -f "$guest_dest" ]]; then
          guest_have="$(sha256_file "$guest_dest")"
          if [[ "$guest_have" != "$guest_sha" ]]; then
            (( force == 1 )) || die "guest BusyBox cache for $guest_arch differs from bundle (use --force to replace)"
            install -m 0755 "$tmp/extras/guest-busybox" "$guest_dest"
          fi
        else
          install -m 0755 "$tmp/extras/guest-busybox" "$guest_dest"
        fi
        cat >> "$dest/bundle.env" <<EOF_GUEST
BUNDLE_GUEST_USERSPACE_SPEC=busybox-static
BUNDLE_GUEST_USERSPACE_KIND=busybox-static
BUNDLE_GUEST_BUSYBOX=$(quote_env "$guest_dest")
BUNDLE_GUEST_ARCH=$(quote_env "$guest_arch")
EOF_GUEST
        say "Imported guest userspace busybox-static/$guest_arch -> $guest_dest"
        ;;
      buildroot-minimal|buildroot-network|buildroot-ssh)
        local brver brprofile brdest brmeta brhave brdef brcfgsha brsrcsha sdksha sdkdest sdkdir
        [[ -f "$tmp/extras/guest-rootfs.tar" ]] || die "bundle manifest declares Buildroot userspace but payload is missing"
        [[ "$(sha256_file "$tmp/extras/guest-rootfs.tar")" == "$guest_sha" ]] || die "Buildroot guest rootfs checksum mismatch"
        brver="$(json_get "$tmp/manifest.json" guest_userspace.buildroot_version)"; [[ -n "$brver" ]] || die "Buildroot userspace manifest lacks version"
        brprofile="$(json_get "$tmp/manifest.json" guest_userspace.profile)"; [[ -n "$brprofile" ]] || brprofile="${guest_kind#buildroot-}"
        brdef="$(json_get "$tmp/manifest.json" guest_userspace.defconfig 2>/dev/null || true)"
        brcfgsha="$(json_get "$tmp/manifest.json" guest_userspace.config_sha256 2>/dev/null || true)"
        brsrcsha="$(json_get "$tmp/manifest.json" guest_userspace.source_sha256 2>/dev/null || true)"
        brdest="$GUESTS/buildroot/$brver/$brprofile/$guest_arch/rootfs.tar"; brmeta="$(dirname "$brdest")/metadata.env"
        mkdir -p "$(dirname "$brdest")"
        [[ -f "$tmp/extras/buildroot.config" && -f "$tmp/extras/busybox.fragment" ]] || die "Buildroot userspace bundle lacks configuration provenance files"
        if [[ -f "$brdest" ]]; then
          brhave="$(sha256_file "$brdest")"
          if [[ "$brhave" != "$guest_sha" ]]; then
            (( force == 1 )) || die "Buildroot userspace cache for $brver/$brprofile/$guest_arch differs from bundle (use --force to replace)"
            cp "$tmp/extras/guest-rootfs.tar" "$brdest"
          fi
        else
          cp "$tmp/extras/guest-rootfs.tar" "$brdest"
        fi
        cp "$tmp/extras/buildroot.config" "$(dirname "$brdest")/buildroot.config"
        cp "$tmp/extras/busybox.fragment" "$(dirname "$brdest")/busybox.fragment"
        cat > "$brmeta" <<EOF_BR_META
KLAB_GUEST_USERSPACE=buildroot:$brprofile
KLAB_GUEST_ARCH=$guest_arch
KLAB_BUILDROOT_VERSION=$brver
KLAB_BUILDROOT_DEFCONFIG=$brdef
KLAB_BUILDROOT_ROOTFS_SHA256=$guest_sha
KLAB_BUILDROOT_CONFIG_SHA256=$brcfgsha
KLAB_BUILDROOT_SOURCE_SHA256=$brsrcsha
EOF_BR_META
        sdksha="$(json_get "$tmp/manifest.json" guest_userspace.sdk.sha256 2>/dev/null || true)"
        sdkdir=""
        if [[ -n "$sdksha" ]]; then
          [[ -f "$tmp/extras/buildroot-sdk.tar.gz" ]] || die "bundle manifest declares Buildroot SDK but payload is missing"
          [[ "$(sha256_file "$tmp/extras/buildroot-sdk.tar.gz")" == "$sdksha" ]] || die "Buildroot SDK checksum mismatch"
          sdkdest="$(dirname "$brdest")/sdk.tar.gz"; sdkdir="$(dirname "$brdest")/sdk"
          if [[ -f "$sdkdest" && "$(sha256_file "$sdkdest")" != "$sdksha" && "$force" != 1 ]]; then
            die "Buildroot SDK cache for $brver/$brprofile/$guest_arch differs from bundle (use --force to replace)"
          fi
          cp "$tmp/extras/buildroot-sdk.tar.gz" "$sdkdest"
          rm -rf "$sdkdir"; mkdir -p "$sdkdir"; tar -xzf "$sdkdest" -C "$sdkdir" --strip-components=1 || die "failed to extract Buildroot SDK"
          [[ -x "$sdkdir/relocate-sdk.sh" ]] || die "imported Buildroot SDK lacks relocate-sdk.sh"
          (cd "$sdkdir" && ./relocate-sdk.sh) || die "Buildroot SDK relocation failed"
          cat >> "$brmeta" <<EOF_BR_SDK
KLAB_BUILDROOT_SDK_SHA256=$sdksha
KLAB_BUILDROOT_SDK_ARCHIVE=$sdkdest
KLAB_BUILDROOT_SDK_DIR=$sdkdir
EOF_BR_SDK
        fi
        cat >> "$dest/bundle.env" <<EOF_GUEST
BUNDLE_GUEST_USERSPACE_SPEC=buildroot:$brprofile
BUNDLE_GUEST_USERSPACE_KIND=buildroot-$brprofile
BUNDLE_GUEST_ROOTFS=$(quote_env "$brdest")
BUNDLE_GUEST_SDK=$(quote_env "$sdkdir")
BUNDLE_BUILDROOT_VERSION=$(quote_env "$brver")
BUNDLE_GUEST_ARCH=$(quote_env "$guest_arch")
EOF_GUEST
        say "Imported guest userspace Buildroot $brver/$brprofile/$guest_arch -> $brdest"
        [[ -n "$sdkdir" ]] && say "Imported Buildroot SDK -> $sdkdir"
        ;;
      native)
        local native_provider native_release native_dest native_meta_dest native_have native_meta_sha
        native_provider="$(json_get "$tmp/manifest.json" guest_userspace.provider)"
        native_release="$(json_get "$tmp/manifest.json" guest_userspace.release)"
        [[ -n "$native_provider" && -n "$native_release" ]] || die "native userspace manifest lacks provider or release"
        [[ -f "$tmp/extras/native-rootfs.tar.zst" && -f "$tmp/extras/native-metadata.env" ]] || die "native userspace payload is incomplete"
        [[ "$(sha256_file "$tmp/extras/native-rootfs.tar.zst")" == "$guest_sha" ]] || die "native guest rootfs checksum mismatch"
        native_meta_sha="$(json_get "$tmp/manifest.json" guest_userspace.metadata_sha256)"
        [[ "$(sha256_file "$tmp/extras/native-metadata.env")" == "$native_meta_sha" ]] || die "native guest metadata checksum mismatch"
        native_dest="$(native_rootfs_path "$native_provider" "$native_release" "$guest_arch")"
        native_meta_dest="$(native_metadata_path "$native_provider" "$native_release" "$guest_arch")"
        mkdir -p "$(dirname "$native_dest")"
        if [[ -f "$native_dest" ]]; then
          native_have="$(sha256_file "$native_dest")"
          if [[ "$native_have" != "$guest_sha" ]]; then
            (( force == 1 )) || die "native userspace cache for $native_provider:$native_release/$guest_arch differs from bundle (use --force to replace)"
            cp "$tmp/extras/native-rootfs.tar.zst" "$native_dest"
          fi
        else
          cp "$tmp/extras/native-rootfs.tar.zst" "$native_dest"
        fi
        cp "$tmp/extras/native-metadata.env" "$native_meta_dest"
        cat >> "$dest/bundle.env" <<EOF_GUEST
BUNDLE_GUEST_USERSPACE_SPEC=native:$native_provider:$native_release
BUNDLE_GUEST_USERSPACE_KIND=native
BUNDLE_GUEST_ROOTFS=$(quote_env "$native_dest")
BUNDLE_GUEST_ARCH=$(quote_env "$guest_arch")
EOF_GUEST
        say "Imported native userspace $native_provider:$native_release/$guest_arch -> $native_dest"
        ;;
      *) die "unsupported guest userspace kind '$guest_kind'" ;;
    esac
  fi

  if [[ -f "$tmp/extras/toolchain.tar.zst" ]]; then
    local tc_id tc_sha tc_cc_rel tc_family tc_version tc_target tc_prefix_rel tc_bin_rel tc_dest tc_tree_sha tc_boundary_json
    tc_id="$(json_get "$tmp/manifest.json" toolchain.id 2>/dev/null || true)"
    [[ -n "$tc_id" ]] || tc_id="$(sanitize_id "$(json_get "$tmp/manifest.json" toolchain.name)")"
    tc_sha="$(json_get "$tmp/manifest.json" toolchain.sha256)"
    tc_cc_rel="$(json_get "$tmp/manifest.json" toolchain.cc_relpath 2>/dev/null || true)"
    tc_family="$(json_get "$tmp/manifest.json" toolchain.family 2>/dev/null || true)"
    tc_version="$(json_get "$tmp/manifest.json" toolchain.version 2>/dev/null || true)"
    tc_target="$(json_get "$tmp/manifest.json" toolchain.target 2>/dev/null || true)"
    tc_prefix_rel="$(json_get "$tmp/manifest.json" toolchain.cross_prefix_relpath 2>/dev/null || true)"
    tc_bin_rel="$(json_get "$tmp/manifest.json" toolchain.bin_dir_relpath 2>/dev/null || true)"
    tc_tree_sha="$(json_get "$tmp/manifest.json" toolchain.tree_sha256 2>/dev/null || true)"
    [[ -n "$tc_cc_rel" ]] || die "bundle contains a legacy unbound toolchain; recreate it with the current klab-bundle.sh"
    mkdir -p "$TOOLCHAINS"
    tc_dest="$(toolchain_import_dest "$TOOLCHAINS" "$tc_id" "$tc_sha")"
    if [[ -d "$tc_dest" ]]; then
      if [[ -f "$tc_dest/.klab-toolchain.sha256" && "$(cat "$tc_dest/.klab-toolchain.sha256")" == "$tc_sha" ]]; then
        say "Reusing already imported bound toolchain $tc_id ($tc_sha)"
      elif (( force == 1 )); then
        # This can only be a corrupt content-addressed destination. Never
        # replace a different archive at the stable logical-ID path.
        rm -rf "$tc_dest"; mkdir -p "$tc_dest"
        tar --zstd -xf "$tmp/extras/toolchain.tar.zst" -C "$tc_dest"
      else
        die "toolchain archive destination '$tc_dest' exists with different content (use --force to repair it)"
      fi
    else
      mkdir -p "$tc_dest"
      tar --zstd -xf "$tmp/extras/toolchain.tar.zst" -C "$tc_dest"
    fi
    printf '%s\n' "$tc_sha" > "$tc_dest/.klab-toolchain.sha256"
    mkdir -p "$dest/extras"
    rm -f "$dest/extras/toolchain"
    ln -s "$tc_dest" "$dest/extras/toolchain"
    [[ -x "$tc_dest/$tc_cc_rel" ]] || die "bound compiler missing after import: $tc_dest/$tc_cc_rel"
    if [[ -n "$tc_tree_sha" || -f "$tc_dest/.klab-toolchain-boundary.json" ]]; then
      local __tc_args=(verify --root "$tc_dest" --cc "$tc_cc_rel" --family "${tc_family:-gcc}")
      [[ -n "$tc_tree_sha" ]] && __tc_args+=(--tree-sha256 "$tc_tree_sha")
      [[ -n "$tc_version" ]] && __tc_args+=(--version "$tc_version")
      [[ -n "$tc_target" ]] && __tc_args+=(--target "$tc_target")
      tc_boundary_json="$("$TOOLCHAIN_BOUNDARY_BIN" "${__tc_args[@]}" --json)"
      tc_tree_sha="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["tree_sha256"])' "$tc_boundary_json")"
    fi

    cat >> "$dest/bundle.env" <<EOFENV
BUNDLE_TOOLCHAIN_BOUND=1
BUNDLE_TOOLCHAIN_ID=$(quote_env "$tc_id")
BUNDLE_TOOLCHAIN_DIR=$(quote_env "$tc_dest")
BUNDLE_TOOLCHAIN_CC_REL=$(quote_env "$tc_cc_rel")
BUNDLE_TOOLCHAIN_CC=$(quote_env "$tc_dest/$tc_cc_rel")
BUNDLE_TOOLCHAIN_FAMILY=$(quote_env "$tc_family")
BUNDLE_TOOLCHAIN_VERSION=$(quote_env "$tc_version")
BUNDLE_TOOLCHAIN_TARGET=$(quote_env "$tc_target")
BUNDLE_TOOLCHAIN_CROSS_PREFIX_REL=$(quote_env "$tc_prefix_rel")
BUNDLE_TOOLCHAIN_CROSS_PREFIX=$(quote_env "${tc_prefix_rel:+$tc_dest/$tc_prefix_rel}")
BUNDLE_TOOLCHAIN_BIN_DIR=$(quote_env "$tc_dest/${tc_bin_rel:-bin}")
BUNDLE_TOOLCHAIN_ARCHIVE_SHA256=$(quote_env "$tc_sha")
BUNDLE_TOOLCHAIN_TREE_SHA256=$(quote_env "$tc_tree_sha")
EOFENV
    say "Imported and bound toolchain $tc_id -> $tc_dest"
  fi

  if [[ -f "$tmp/extras/container-image.tar.zst" ]]; then
    mkdir -p "$dest/extras"
    cp "$tmp/extras/container-image.tar.zst" "$dest/extras/container-image.tar.zst"
    if (( load_image == 1 )); then
      local rt; rt="$(container_runtime)"
      say "Loading bundled container image using $rt"
      zstd -dc "$tmp/extras/container-image.tar.zst" | "$rt" load
    else
      say "Container image preserved at $dest/extras/container-image.tar.zst (use --load-image to load it)"
    fi
  fi

  cp "$tmp/manifest.json" "$dest/klab-manifest.json"
  cp "$tmp/SHA256SUMS" "$dest/klab-SHA256SUMS"
  # KLAB_ATOMIC_TARGET_IMPORT_M2: commit the fully assembled target. If the
  # final rename fails after moving the previous target aside, restore it.
  if [[ -n "$__atomic_final" ]]; then
    if [[ -e "$__atomic_final" ]]; then
      __atomic_old="${__atomic_final}.klab-old.$$"
      remove_tree "$__atomic_old"
      mv -- "$__atomic_final" "$__atomic_old" || die "could not stage existing target for atomic replacement: $__atomic_final"
    fi
    if ! mv -- "$dest" "$__atomic_final"; then
      [[ -z "$__atomic_old" || ! -e "$__atomic_old" ]] || mv -- "$__atomic_old" "$__atomic_final" || true
      die "could not atomically install target: $__atomic_final"
    fi
    __atomic_tmp=""
    [[ -z "$__atomic_old" ]] || remove_tree "$__atomic_old"
    dest="$__atomic_final"
  fi
  printf '%s\n' "$dest"
}


fixup_freebsd_env() {
  local dest="$1" manifest="$2" target release arch caps
  target="$(json_get "$manifest" target)"
  release="$(json_get "$manifest" release)"
  arch="$(canonical_arch "$(json_get "$manifest" arch)")"
  caps="$(json_get "$manifest" capabilities 2>/dev/null || true)"
  if [[ "$caps" == \[* ]]; then
    caps="$(python3 - "$manifest" <<'PY_CAPS'
import json,sys
m=json.load(open(sys.argv[1]))
print(','.join(m.get('capabilities') or []))
PY_CAPS
)"
  fi
  [[ -n "$arch" ]] || arch="${target##*:}"
  cat > "$dest/bundle.env" <<EOF_FBSD_IMPORT
BUNDLE_PROVIDER=freebsd
BUNDLE_BACKEND=freebsd
BUNDLE_TARGET_ID=$(quote_env "$target")
BUNDLE_DISTRO_RELEASE=$(quote_env "$release")
BUNDLE_KERNEL_RELEASE=$(quote_env "$arch")
BUNDLE_OS_RELEASE=$(quote_env "$release")
BUNDLE_ARCH=$(quote_env "$arch")
BUNDLE_DIR=$(quote_env "$dest")
BUNDLE_DISK_IMAGE=$(quote_env "$dest/freebsd-base.qcow2")
BUNDLE_SEED_ISO=$(quote_env "$dest/cidata.iso")
BUNDLE_SOURCE_ISO=$(quote_env "$dest/source.iso")
BUNDLE_SOURCE_ARCHIVE=$(quote_env "$dest/packages/src.txz")
BUNDLE_PACKAGES=$(quote_env "$dest/packages")
BUNDLE_BOOT_TYPE=disk
BUNDLE_CAPABILITIES=$(quote_env "$caps")
BUNDLE_IMPORTED_FROM_KLAB=1
EOF_FBSD_IMPORT
  [[ -f "$dest/freebsd-base.qcow2" ]] || die "imported FreeBSD bundle is missing freebsd-base.qcow2"
  [[ -f "$dest/cidata.iso" ]] || die "imported FreeBSD bundle is missing cidata.iso"
  [[ -f "$dest/source.iso" ]] || die "imported FreeBSD bundle is missing source.iso"
}

cmd_create_freebsd() {
  need_common
  (($# >= 1)) || { usage; exit 2; }
  local target="$1"; shift
  local output="" profile="normal"
  while (($#)); do
    case "$1" in
      -o|--output) [[ $# -ge 2 ]] || die "$1 needs a value"; output="$2"; shift 2 ;;
      --profile) [[ $# -ge 2 ]] || die "$1 needs a value"; profile="$2"; shift 2 ;;
      --auto-toolchain|--include-toolchain|--toolchain-id|--toolchain-cc|--include-image)
        die "FreeBSD bundles use the compiler/toolchain inside the FreeBSD guest; '$1' is not applicable" ;;
      *) die "unknown create option '$1'" ;;
    esac
  done
  [[ "$profile" == normal ]] || die "FreeBSD release targets do not use Linux build profiles"
  parse_target "$target"
  [[ "$PROVIDER" == freebsd && -n "$KERNEL_RELEASE" ]] || die "FreeBSD target syntax: freebsd:<release>:<arch>"
  local bundle stage payload sha safe caps_json output_abs arch
  arch="$(canonical_arch "$KERNEL_RELEASE")"
  target="freebsd:$DISTRO_RELEASE:$arch"
  bundle="$(bundle_existing_dir_for freebsd "$DISTRO_RELEASE" "$arch" "$arch")"
  [[ -f "$bundle/bundle.env" ]] || die "FreeBSD target is not cached: $target; run kernel-lab.sh prepare/fetch first"
  safe="$(safe_name "$target")"
  [[ -n "$output" ]] || output="$PWD/${safe}.klab"
  [[ "$output" == *.klab ]] || output="$output.klab"
  output_abs="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$output")"
  stage="$(mktemp -d)"; trap "rm -rf '$stage'" EXIT
  mkdir -p "$stage/payload" "$stage/extras"
  printf '%s\n' "$FORMAT_VERSION" > "$stage/FORMAT_VERSION"
  payload="$stage/payload/freebsd-bundle.tar.zst"
  say "Packing cached FreeBSD bundle $target"
  tar -C "$bundle" --zstd -cf "$payload" .
  sha="$(sha256_file "$payload")"
  add_checksum_line "$stage" payload/freebsd-bundle.tar.zst
  caps_json="$(python3 - "$bundle/bundle.env" <<'PY_FBSD_META'
import json,shlex,sys
caps=[]
for line in open(sys.argv[1],encoding='utf-8'):
    if line.startswith('BUNDLE_CAPABILITIES='):
        v=line.split('=',1)[1].strip()
        try: v=shlex.split(v)[0] if v else ''
        except Exception: pass
        caps=[x for x in v.split(',') if x]
print(json.dumps(caps))
PY_FBSD_META
)"
  local arch_plan
  arch_plan="$(klab_arch_plan_json "$arch" "$(klab_arch_host)")"
  FORMAT_NAME="$FORMAT_NAME" FORMAT_VERSION="$FORMAT_VERSION" ARCH="$arch" ARCH_PLAN="$arch_plan" TARGET="$target" RELEASE="$DISTRO_RELEASE" CAPS_JSON="$caps_json" SHA="$sha" \
  python3 - "$stage/manifest.json" <<'PY_FBSD_MANIFEST'
import datetime,json,os,sys
m={
 "format":os.environ["FORMAT_NAME"],"format_version":int(os.environ["FORMAT_VERSION"]),
 "created_at":datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace('+00:00','Z'),
 "arch":os.environ["ARCH"],"architecture_model":json.loads(os.environ["ARCH_PLAN"]),"kind":"freebsd","backend":"freebsd","target":os.environ["TARGET"],
 "profile":None,"provider":"freebsd","release":os.environ["RELEASE"],"kernel_release":os.environ["ARCH"],
 "build_image":None,"upstream_ref":None,"capabilities":json.loads(os.environ.get("CAPS_JSON","[]")),
 "payloads":[{"role":"freebsd-bundle","path":"payload/freebsd-bundle.tar.zst","sha256":os.environ["SHA"]}],
 "toolchain":None,"container_image":None,
}
with open(sys.argv[1],'w',encoding='utf-8') as f: json.dump(m,f,indent=2,sort_keys=True); f.write('\n')
PY_FBSD_MANIFEST
  add_checksum_line "$stage" manifest.json
  sort -k2 -o "$stage/SHA256SUMS" "$stage/SHA256SUMS"
  mkdir -p "$(dirname "$output_abs")"
  say "Creating $output_abs"
  tar -C "$stage" --zstd -cf "$output_abs" FORMAT_VERSION manifest.json SHA256SUMS payload extras
  printf '%s  %s\n' "$(sha256_file "$output_abs")" "$output_abs"
}

cmd_create() {
  (($# >= 1)) || { usage; exit 2; }
  case "$1" in
    freebsd:*) cmd_create_freebsd "$@" ;;
    *) cmd_create_legacy "$@" ;;
  esac
}

cmd_import_freebsd() {
  need_common
  (($# >= 1)) || { usage; exit 2; }
  local file="$1"; shift
  local force=0
  while (($#)); do
    case "$1" in
      --force) force=1 ;;
      --load-image) : ;;
      *) die "unknown import option '$1'" ;;
    esac
    shift
  done
  local tmp kind target release arch dest
  tmp="$(mktemp -d)"; trap "rm -rf '$tmp'" EXIT
  extract_outer "$file" "$tmp"; verify_stage "$tmp"
  kind="$(json_get "$tmp/manifest.json" kind)"; [[ "$kind" == freebsd ]] || die "not a FreeBSD bundle"
  target="$(json_get "$tmp/manifest.json" target)"; release="$(json_get "$tmp/manifest.json" release)"; arch="$(json_get "$tmp/manifest.json" kernel_release)"
  dest="$(bundle_dir_for freebsd "$release" "$arch" "$arch")"
  if [[ -e "$dest" ]]; then (( force == 1 )) || die "destination already exists: $dest (use --force to replace)"; rm -rf "$dest"; fi
  mkdir -p "$dest"
  say "Importing $target to $dest"
  tar --zstd -xf "$tmp/payload/freebsd-bundle.tar.zst" -C "$dest"
  fixup_freebsd_env "$dest" "$tmp/manifest.json"
  cp "$tmp/manifest.json" "$dest/klab-manifest.json"; cp "$tmp/SHA256SUMS" "$dest/klab-SHA256SUMS"
  printf '%s\n' "$dest"
}

cmd_import() {
  (($# >= 1)) || { usage; exit 2; }
  local file="$1" tmp kind
  tmp="$(mktemp -d)"
  extract_outer "$file" "$tmp"
  kind="$(json_get "$tmp/manifest.json" kind 2>/dev/null || true)"
  rm -rf "$tmp"
  if [[ "$kind" == freebsd ]]; then cmd_import_freebsd "$@"; else cmd_import_legacy "$@"; fi
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    create|export) shift; cmd_create "$@" ;;
    verify) shift; cmd_verify "$@" ;;
    inspect) shift; cmd_inspect "$@" ;;
    import) shift; cmd_import "$@" ;;
    -h|--help|help|'') usage ;;
    *) usage; die "unknown command '$cmd'" ;;
  esac
}

main "$@"
