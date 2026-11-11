#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source "$SELF/lib/klab-root.sh"
die(){ printf 'klab-container-export: ERROR: %s\n' "$*" >&2; exit 1; }
say(){ printf '==> %s\n' "$*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }
usage(){ cat <<'EOF'
Usage:
  klab export container --target TARGET[@ARCH] [--target TARGET[@ARCH] ...]
      [--targets-file FILE] [--profile userspace|build|full]
      [--tag IMAGE] [--output FILE.oci.tar] [--base-image IMAGE]
      [--runtime podman|docker] [--context-only DIR]

Profiles:
  userspace  Native target userspace for fast tool/runtime tests.
  build      Minimal userspace, SDK, headers and exact build artifacts.
  full       SSH guest userspace, SDK and complete QEMU target artifacts.

A targets file contains one selector per line. Blank and # comment lines are ignored.
EOF
}
runtime="${KLAB_CONTAINER_RUNTIME:-}"; profile=full; tag=""; output=""; base="ubuntu:24.04"
context_only=""; targets_file=""; targets=()
while (($#)); do
  case "$1" in
    --target) (($#>=2)) || die '--target needs a value'; targets+=("$2"); shift 2;;
    --targets-file) (($#>=2)) || die '--targets-file needs a value'; targets_file="$2"; shift 2;;
    --profile) (($#>=2)) || die '--profile needs a value'; profile="$2"; shift 2;;
    --tag) (($#>=2)) || die '--tag needs a value'; tag="$2"; shift 2;;
    -o|--output) (($#>=2)) || die "$1 needs a value"; output="$2"; shift 2;;
    --base-image) (($#>=2)) || die '--base-image needs a value'; base="$2"; shift 2;;
    --runtime) (($#>=2)) || die '--runtime needs a value'; runtime="$2"; shift 2;;
    --context-only) (($#>=2)) || die '--context-only needs a directory'; context_only="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "unknown option '$1'";;
  esac
done
case "$profile" in userspace|build|full) ;; *) die "profile must be userspace, build, or full";; esac
if [[ -n "$targets_file" ]]; then
  [[ -f "$targets_file" ]] || die "targets file not found: $targets_file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"; line="${line#"$(printf '%s' "$line" | sed 's/^[[:space:]]*//')"}"
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -n "$line" ]] && targets+=("$line")
  done < "$targets_file"
fi
((${#targets[@]})) || die 'at least one --target or --targets-file entry is required'
declare -A seen=(); unique=()
for selector in "${targets[@]}"; do
  [[ "$selector" =~ ^[A-Za-z0-9._:+~@-]+$ ]] || die "invalid target selector '$selector'"
  [[ -n "${seen[$selector]:-}" ]] && continue
  seen[$selector]=1; unique+=("$selector")
done
targets=("${unique[@]}")
safe_tag="$(printf '%s' "${tag:-klab-selected-$profile}" | tr '/:' '--' | tr -cd 'A-Za-z0-9_.-')"
[[ -n "$tag" ]] || tag="klab-selected-$profile:latest"
[[ -n "$output" ]] || output="$PWD/$safe_tag.oci.tar"
output="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$output")"
if [[ -n "$context_only" ]]; then
  context="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$context_only")"
  [[ ! -e "$context" ]] || die "context destination already exists: $context"
  mkdir -p "$context"; cleanup=0
else context="$(mktemp -d)"; cleanup=1
fi
trap '((cleanup==0)) || rm -rf "$context"' EXIT
mkdir -p "$context/klab" "$context/transfer"
tar -C "$SELF" --exclude=.git --exclude=library --exclude=work --exclude='*.oci.tar' -cf - . | tar -C "$context/klab" -xf -
manifest="$context/selection.tsv"
printf 'selector\ttarget\tarch\tbundle\tsha256\n' > "$manifest"
for selector in "${targets[@]}"; do
  target="$selector"; arch=x86_64
  if [[ "$selector" == *@* ]]; then target="${selector%@*}"; arch="${selector##*@}"; fi
  if [[ "$target" == freebsd:*:* && "$selector" != *@* ]]; then arch="${target##*:}"; fi
  safe="$(printf '%s-%s' "$target" "$arch" | tr ':/' '--' | tr -cd 'A-Za-z0-9_.+-')"
  bundle="$context/transfer/$safe.klab"; args=(create "$target" -o "$bundle")
  [[ "$target" == freebsd:* ]] || {
    case "$profile" in
      userspace) provider="${target%%:*}"; rest="${target#*:}"; release="${rest%%:*}"; args+=(--userspace "native:$provider:$release");;
      build) args+=(--userspace buildroot:minimal --include-sdk);;
      full) args+=(--userspace buildroot:ssh --include-sdk);;
    esac
  }
  say "Packing $selector ($profile)"
  KLAB_ARCH="$arch" "$SELF/klab-bundle.sh" "${args[@]}" >/dev/null
  if [[ "$target" != upstream:* && "$target" != freebsd:* ]]; then
    provider="${target%%:*}"; rest="${target#*:}"; release="${rest%%:*}"; kernel="${rest#*:}"
    env="$KLAB_ROOT/targets/kernels/$provider/$release/$arch/$kernel/bundle.env"
    [[ -f "$env" ]] || die "cached target metadata disappeared: $env"
    unset BUNDLE_BUILDENV_FILE BUNDLE_DISTRO_TOOLCHAIN_FILE
    source "$env"
    for dependency in "${BUNDLE_DISTRO_TOOLCHAIN_FILE:-}" "${BUNDLE_BUILDENV_FILE:-}"; do
      [[ -z "$dependency" ]] && continue
      [[ -f "$dependency" ]] || die "referenced artifact is missing: $dependency"
      cp -n "$dependency" "$context/transfer/"
    done
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$selector" "$target" "$arch" "$(basename "$bundle")" "$(sha256sum "$bundle" | awk '{print $1}')" >> "$manifest"
done
(cd "$context/transfer" && sha256sum ./* | LC_ALL=C sort -k2 > SHA256SUMS)
cat > "$context/entrypoint.sh" <<'EOF_ENTRY'
#!/usr/bin/env bash
set -Eeuo pipefail
export KLAB_ROOT="${KLAB_ROOT:-/var/lib/klab}"
if [[ ! -f "$KLAB_ROOT/state/.container-imported" ]]; then
  /opt/klab/klab setup --root "$KLAB_ROOT" >/dev/null
  /opt/klab/klab load /opt/klab-transfer >/dev/null
  mkdir -p "$KLAB_ROOT/state"; : > "$KLAB_ROOT/state/.container-imported"
fi
if (($#==0)); then exec /bin/bash; fi
if [[ "$1" == klab ]]; then shift; fi
exec /opt/klab/klab "$@"
EOF_ENTRY
chmod +x "$context/entrypoint.sh"
cat > "$context/Containerfile" <<EOF_CONTAINER
FROM $base
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends bash python3 zstd tar cpio gzip xz-utils openssh-client make gcc binutils iproute2 qemu-system-x86 qemu-system-arm qemu-system-mips qemu-utils && rm -rf /var/lib/apt/lists/*
COPY klab /opt/klab
COPY transfer /opt/klab-transfer
COPY selection.tsv /opt/klab-selection.tsv
COPY entrypoint.sh /usr/local/bin/klab-container-entrypoint
RUN chmod +x /opt/klab/klab /opt/klab/*.sh /usr/local/bin/klab-container-entrypoint && mkdir -p /var/lib/klab
ENV KLAB_ROOT=/var/lib/klab KLAB_CONTAINER_BUNDLE_PROFILE=$profile
VOLUME ["/var/lib/klab", "/workspace"]
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/klab-container-entrypoint"]
CMD ["targets"]
EOF_CONTAINER
printf '{"format":"klab-container-selection","format_version":1,"profile":"%s","image":"%s","base_image":"%s","target_count":%d}\n' "$profile" "$tag" "$base" "${#targets[@]}" > "$context/export-manifest.json"
if [[ -n "$context_only" ]]; then say "Container build context ready: $context"; printf '%s\n' "$context"; exit 0; fi
if [[ -z "$runtime" ]]; then
  if have podman; then runtime=podman; elif have docker; then runtime=docker; else die 'podman or docker is required (or use --context-only)'; fi
fi
have "$runtime" || die "container runtime not found: $runtime"
say "Building $tag with $runtime"; "$runtime" build -t "$tag" -f "$context/Containerfile" "$context"
mkdir -p "$(dirname "$output")"; tmp="$output.tmp.$$"; rm -f "$tmp"
if [[ "$runtime" == podman ]]; then "$runtime" save --format oci-archive -o "$tmp" "$tag"
elif have skopeo; then skopeo copy "docker-daemon:$tag" "oci-archive:$tmp:$tag"
else "$runtime" save -o "$tmp" "$tag"; say 'skopeo unavailable; output uses Docker archive encoding'; fi
mv "$tmp" "$output"; sha256sum "$output" > "$output.sha256"; say "Ready: $output"; printf '%s\n' "$output"
