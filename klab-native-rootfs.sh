#!/usr/bin/env bash
set -euo pipefail

KLAB_ROOT="${KLAB_ROOT:-${HOME}/klab}"
STORE="${KLAB_NATIVE_ROOTFS_STORE:-$KLAB_ROOT/artifacts/userspaces/native}"
RUNTIME="${KLAB_CONTAINER_RUNTIME:-docker}"
ARCH="${KLAB_ARCH:-x86_64}"
CAPTURE_CID=""
CAPTURE_TMP=""

rootless_foreign_capture() {
  local provider="$1" release="$2" arch="$3" platform="$4" image="$5" dir="$6" out="$7" meta="$8"
  local toolroot proot qemu work root cid tmp iid digests created sha
  [[ "$provider" == ubuntu || "$provider" == debian ]] || die "rootless foreign capture is currently implemented for APT providers"
  toolroot="${KLAB_ROOTLESS_USEREMU_ROOT:-$KLAB_ROOT/bin/rootless-useremu/root}"
  proot="$toolroot/usr/bin/proot"; qemu="$toolroot/usr/bin/qemu-${arch}-static"
  [[ -x "$proot" && -x "$qemu" ]] || die "foreign native capture requires local proot and qemu-${arch}-static under $toolroot"
  work="$(mktemp -d "$KLAB_ROOT/work/native-${provider}-${release}-${arch}.XXXXXX")"; root="$work/root"; tmp="$out.part.$$"
  mkdir -p "$root" "$dir"
  CAPTURE_TMP="$tmp"
  cid="$("$RUNTIME" create --platform "$platform" "$image" /bin/true)"; CAPTURE_CID="$cid"
  "$RUNTIME" export "$cid" | tar -xf - -C "$root"
  "$RUNTIME" rm -f "$cid" >/dev/null; CAPTURE_CID=""; cid=""
  say "installing rootless native SSH package set in $image via qemu-user/proot"
  env -u LD_PRELOAD PROOT_NO_SECCOMP=1 "$proot" -0 -q "$qemu" -R "$root" /bin/sh -ec '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    init_package=; apt-cache policy systemd-sysv | grep -Eq "Candidate: [^ (]" && init_package=systemd-sysv
    iproute_package=iproute2; apt-cache policy iproute2 | grep -Eq "Candidate: [^ (]" || iproute_package=iproute
    kmod_package=kmod; apt-cache policy kmod | grep -Eq "Candidate: [^ (]" || kmod_package=module-init-tools
    apt-get install -y --download-only --no-install-recommends --no-upgrade $init_package openssh-server "$iproute_package" iputils-ping ethtool net-tools procps "$kmod_package" gcc make libc6-dev python3 ca-certificates curl
  '
  while IFS= read -r -d '' deb; do dpkg-deb --fsys-tarfile "$deb" | tar --keep-directory-symlink -xf - -C "$root"; done < <(find "$root/var/cache/apt/archives" -type f -name '*.deb' -print0)
  rm -f "$root/var/cache/apt/archives"/*.deb
  rm -rf "$root/var/lib/apt/lists"/*
  # Payload extraction supplies the distro files directly. KLab starts sshd
  # with PAM disabled and generates host keys when the guest boots.
  while IFS= read -r -d '' file; do mv "$file" "${file%.dpkg-new}"; done < <(find "$root" -type f -name '*.dpkg-new' -print0)
  if [[ ! -s "$root/etc/ssh/sshd_config" && -s "$root/usr/share/openssh/sshd_config" ]]; then
    cp "$root/usr/share/openssh/sshd_config" "$root/etc/ssh/sshd_config"
  fi
  if ! grep -q '^sshd:' "$root/etc/passwd"; then
    printf 'sshd:x:101:65534::/run/sshd:/usr/sbin/nologin\n' >> "$root/etc/passwd"
    printf 'sshd:*:19000:0:99999:7:::\n' >> "$root/etc/shadow"
  fi
  [[ -x "$root/usr/sbin/sshd" && -x "$root/sbin/ip" || -x "$root/usr/sbin/ip" ]] || { rm -rf "$work"; die "rootless native capture did not extract sshd and iproute"; }
  env -u LD_PRELOAD "$proot" -0 -q "$qemu" -R "$root" /usr/sbin/sshd -t -f /etc/ssh/sshd_config -o HostKey=/dev/null 2>/dev/null || true
  awk '/^Package: /{p=$2} /^Version: /{v=$2} /^Architecture: /{a=$2} /^$/{if(p!="")print p"\t"v"\t"a; p=v=a=""}' "$root/var/lib/dpkg/status" | sort > "$dir/packages.tsv"
  printf 'openssh-server\trootless-payload\t%s\n' "$arch" >> "$dir/packages.tsv"
  tar -C "$root" -cf - etc/apt 2>/dev/null | zstd -T0 -10 -q -f -o "$dir/repositories.tar.zst"
  tar --numeric-owner --owner=0 --group=0 -C "$root" -cf - . | zstd -T0 -10 -q -o "$tmp"
  mv "$tmp" "$out"; CAPTURE_TMP=""
  iid="$("$RUNTIME" image inspect --format '{{.Id}}' "$image")"
  digests="$("$RUNTIME" image inspect --format '{{join .RepoDigests ","}}' "$image")"
  created="$("$RUNTIME" image inspect --format '{{.Created}}' "$image")"
  sha="$(sha256sum "$out" | awk '{print $1}')"
  cat > "$meta" <<META
KLAB_ROOTFS_FORMAT=native-oci-export-tar-zstd-v1
KLAB_ROOTFS_PROVIDER=$provider
KLAB_ROOTFS_RELEASE=$release
KLAB_ROOTFS_ARCH=$arch
KLAB_ROOTFS_IMAGE=$image
KLAB_ROOTFS_IMAGE_ID=$iid
KLAB_ROOTFS_IMAGE_DIGESTS=$digests
KLAB_ROOTFS_IMAGE_CREATED=$created
KLAB_ROOTFS_CAPTURE_MODE=rootless-qemu-proot-payload-v1
KLAB_ROOTFS_SHA256=$sha
KLAB_ROOTFS_PACKAGES_SHA256=$(sha256sum "$dir/packages.tsv" | awk '{print $1}')
KLAB_ROOTFS_REPOSITORIES_SHA256=$(sha256sum "$dir/repositories.tar.zst" | awk '{print $1}')
META
  rm -rf "$work"
  verify "$provider" "$release" "$arch"
  printf '%s\n' "$out"
}

cleanup_capture() {
  [[ -z "$CAPTURE_CID" ]] || "$RUNTIME" rm -f "$CAPTURE_CID" >/dev/null 2>&1 || true
  [[ -z "$CAPTURE_TMP" ]] || rm -f "$CAPTURE_TMP"
}
trap cleanup_capture EXIT

die() { printf 'klab-native-rootfs: ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf 'klab-native-rootfs: %s\n' "$*" >&2; }

canonical_arch() {
  case "$1" in
    x86_64|amd64) echo x86_64 ;;
    i386|i486|i586|i686|x86) echo i386 ;;
    aarch64|arm64) echo aarch64 ;;
    armv7|armv7l|armhf) echo armv7 ;;
    *) die "unsupported native-root architecture '$1'" ;;
  esac
}

platform_for_arch() {
  case "$(canonical_arch "$1")" in
    x86_64) echo linux/amd64 ;;
    i386) echo linux/386 ;;
    aarch64) echo linux/arm64 ;;
    armv7) echo linux/arm/v7 ;;
  esac
}

normalize_provider() {
  case "$1" in
    ubuntu|debian|fedora|centos|alpine|arch) echo "$1" ;;
    *) die "unsupported native-root provider '$1' (expected ubuntu, debian, fedora, centos, alpine, or arch)" ;;
  esac
}

image_for() {
  local provider="$(normalize_provider "$1")" release="$2"
  [[ -n "$release" ]] || die "release is required"
  if [[ "$provider" == centos ]]; then printf 'quay.io/centos/centos:%s\n' "$release"; elif [[ "$provider" == arch ]]; then printf 'archlinux:base\n'; else printf '%s:%s\n' "$provider" "$release"; fi
}

artifact_dir() {
  printf '%s/%s/%s/%s\n' "$STORE" "$(normalize_provider "$1")" "$2" "$(canonical_arch "$3")"
}
rootfs_path() { printf '%s/rootfs.tar.zst\n' "$(artifact_dir "$1" "$2" "$3")"; }
metadata_path() { printf '%s/metadata.env\n' "$(artifact_dir "$1" "$2" "$3")"; }

install_command() {
  local provider="$1" release="${2:-}"
  if [[ "$provider" == ubuntu && ( "$release" == 12.04 || "$release" == 17.04 ) ]]; then
    cat <<'EOF'
sed -i -e 's|http://archive.ubuntu.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|g' -e 's|http://security.ubuntu.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|g' /etc/apt/sources.list
EOF
  fi
  case "$provider" in
    ubuntu|debian)
      cat <<'EOF'
export DEBIAN_FRONTEND=noninteractive
if grep -q '^# deb http://snapshot.debian.org/' /etc/apt/sources.list 2>/dev/null; then
  if ! apt-get update -o Acquire::Retries=3 >/dev/null 2>&1 || ! apt-get install -y --download-only --no-install-recommends systemd >/dev/null 2>&1; then
    sed -i -e '/^deb http:\/\/deb.debian.org\//s/^/# /' -e 's/^# deb http:\/\/snapshot.debian.org/deb http:\/\/snapshot.debian.org/' /etc/apt/sources.list
    printf 'Acquire::Check-Valid-Until "false";\n' >/etc/apt/apt.conf.d/99klab-snapshot
    rm -rf /var/lib/apt/lists/*
  fi
fi
apt-get update
init_package=
apt-cache policy systemd-sysv | grep -Eq 'Candidate: [^ (]' && init_package=systemd-sysv
iproute_package=iproute2
apt-cache policy iproute2 | grep -Eq 'Candidate: [^ (]' || iproute_package=iproute
kmod_package=kmod
apt-cache policy kmod | grep -Eq 'Candidate: [^ (]' || kmod_package=module-init-tools
apt-get install -y --no-install-recommends $init_package openssh-server $iproute_package iputils-ping ethtool net-tools procps $kmod_package gcc make libc6-dev python3 ca-certificates curl
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF
      ;;
    fedora)
      cat <<'EOF'
if command -v dnf >/dev/null 2>&1; then pm=dnf; else pm=yum; fi
"$pm" -y install systemd openssh-server iproute iputils ethtool procps-ng kmod gcc make glibc-devel python3 ca-certificates curl tar
"$pm" clean all
rm -rf /var/cache/dnf/* /var/cache/yum/*
EOF
      ;;
    centos)
      cat <<'EOF'
if grep -q '^VERSION_ID="\?7' /etc/os-release; then
  sed -i -e 's|^mirrorlist=|#mirrorlist=|' -e 's|^#baseurl=http://mirror.centos.org/centos/$releasever|baseurl=https://vault.centos.org/7.9.2009|' /etc/yum.repos.d/CentOS-*.repo
fi
if command -v dnf >/dev/null 2>&1; then pm=dnf; else pm=yum; fi
curl_package=curl
rpm -q curl-minimal >/dev/null 2>&1 && curl_package=curl-minimal
"$pm" -y install systemd openssh-server iproute iputils ethtool procps-ng kmod gcc make glibc-devel python3 ca-certificates "$curl_package" tar
"$pm" clean all
rm -rf /var/cache/dnf/* /var/cache/yum/*
EOF
      ;;
    alpine)
      cat <<'EOF'
apk add --no-cache openrc openssh iproute2 iputils ethtool busybox-extras procps kmod gcc musl-dev make python3 ca-certificates curl
EOF
      ;;
    arch)
      cat <<'EOF'
pacman -Sy --noconfirm
pacman -S --noconfirm --needed systemd openssh iproute2 iputils ethtool procps-ng kmod gcc make glibc python ca-certificates curl tar
pacman -Scc --noconfirm
EOF
      ;;
  esac
}

inventory_command() {
  case "$1" in
    ubuntu|debian) cat <<'EOF'
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' | sort
EOF
      ;;
    fedora|centos) cat <<'EOF'
rpm -qa --qf '%{NAME}\t%{EPOCHNUM}:%{VERSION}-%{RELEASE}\t%{ARCH}\n' | sort
EOF
      ;;
    alpine) echo "apk info -vv | sort" ;;
    arch) cat <<'EOF'
pacman -Q | awk '{print $1 "\t" $2 "\tx86_64"}' | sort
EOF
      ;;
  esac
}

repo_command() {
  case "$1" in
    ubuntu|debian) echo "tar -C / -cf - etc/apt 2>/dev/null" ;;
    fedora) echo 'set -- etc/yum.repos.d; [ ! -d /etc/dnf ] || set -- "$@" etc/dnf; tar -C / -cf - "$@" 2>/dev/null' ;;
    centos) echo "tar -C / -cf - etc/yum.repos.d 2>/dev/null" ;;
    alpine) echo "tar -C / -cf - etc/apk 2>/dev/null" ;;
    arch) echo "tar -C / -cf - etc/pacman.conf etc/pacman.d var/lib/pacman/sync 2>/dev/null" ;;
  esac
}

capture() {
  local provider release arch platform image dir out meta tmp cid iid digests created waited
  provider="$(normalize_provider "$1")"; release="$2"; arch="$(canonical_arch "$3")"
  platform="$(platform_for_arch "$arch")"; image="$(image_for "$provider" "$release")"
  command -v "$RUNTIME" >/dev/null || die "container runtime not found: $RUNTIME"
  command -v zstd >/dev/null || die "zstd is required"
  local image_arch expected_arch
  expected_arch="${platform#linux/}"; expected_arch="${expected_arch%%/*}"
  image_arch="$("$RUNTIME" image inspect --format '{{.Architecture}}' "$image" 2>/dev/null || true)"
  if [[ "$image_arch" != "$expected_arch" ]]; then
    say "pulling $image for $platform (cached architecture: ${image_arch:-none})"
    "$RUNTIME" pull --platform "$platform" "$image"
  fi
  dir="$(artifact_dir "$provider" "$release" "$arch")"; out="$dir/rootfs.tar.zst"; meta="$dir/metadata.env"
  mkdir -p "$dir"; tmp="$out.part.$$"
  if [[ "$arch" != "$(canonical_arch "$(uname -m)")" ]] && ! "$RUNTIME" run --rm --platform "$platform" "$image" /bin/true >/dev/null 2>&1; then
    rootless_foreign_capture "$provider" "$release" "$arch" "$platform" "$image" "$dir" "$out" "$meta"
    return
  fi
  say "installing KLab functional package set in $image"
  cid="$("$RUNTIME" create --platform "$platform" "$image" /bin/sh -ec "$(install_command "$provider" "$release"); touch /tmp/klab-native-ready; exec tail -f /dev/null")"
  CAPTURE_CID="$cid"; CAPTURE_TMP="$tmp"
  "$RUNTIME" start "$cid" >/dev/null
  waited=0
  until "$RUNTIME" exec "$cid" test -f /tmp/klab-native-ready >/dev/null 2>&1; do
    if ! "$RUNTIME" inspect -f '{{.State.Running}}' "$cid" 2>/dev/null | grep -qx true; then
      "$RUNTIME" logs "$cid" >&2 || true
      die "functional package installation failed in container $cid"
    fi
    (( waited < 1800 )) || die "functional package installation timed out in container $cid"
    sleep 1; waited=$((waited + 1))
  done
  "$RUNTIME" exec "$cid" /bin/sh -ec "$(inventory_command "$provider")" > "$dir/packages.tsv"
  "$RUNTIME" exec "$cid" /bin/sh -ec "$(repo_command "$provider")" | zstd -T0 -10 -q -f -o "$dir/repositories.tar.zst"
  "$RUNTIME" export "$cid" | zstd -T0 -10 -q -o "$tmp"
  mv "$tmp" "$out"
  iid="$("$RUNTIME" image inspect --format '{{.Id}}' "$image")"
  digests="$("$RUNTIME" image inspect --format '{{join .RepoDigests ","}}' "$image")"
  created="$("$RUNTIME" image inspect --format '{{.Created}}' "$image")"
  cat > "$meta" <<META
KLAB_ROOTFS_FORMAT=native-oci-export-tar-zstd-v1
KLAB_ROOTFS_PROVIDER=$provider
KLAB_ROOTFS_RELEASE=$release
KLAB_ROOTFS_ARCH=$arch
KLAB_ROOTFS_IMAGE=$image
KLAB_ROOTFS_IMAGE_ID=$iid
KLAB_ROOTFS_IMAGE_DIGESTS=$digests
KLAB_ROOTFS_IMAGE_CREATED=$created
KLAB_ROOTFS_SHA256=$(sha256sum "$out" | awk '{print $1}')
KLAB_ROOTFS_PACKAGES_SHA256=$(sha256sum "$dir/packages.tsv" | awk '{print $1}')
KLAB_ROOTFS_REPOSITORIES_SHA256=$(sha256sum "$dir/repositories.tar.zst" | awk '{print $1}')
META
  "$RUNTIME" rm -f "$cid" >/dev/null; cid=""; CAPTURE_CID=""; CAPTURE_TMP=""
  verify "$provider" "$release" "$arch"
  printf '%s\n' "$out"
}

verify() {
  local provider release arch dir out meta expected actual key file
  provider="$(normalize_provider "$1")"; release="$2"; arch="$(canonical_arch "$3")"
  dir="$(artifact_dir "$provider" "$release" "$arch")"; out="$dir/rootfs.tar.zst"; meta="$dir/metadata.env"
  [[ -s "$out" && -s "$meta" && -s "$dir/packages.tsv" && -s "$dir/repositories.tar.zst" ]] ||
    die "native artifact is incomplete: $provider:$release:$arch"
  while read -r key file; do
    expected="$(sed -n "s/^$key=//p" "$meta")"; actual="$(sha256sum "$file" | awk '{print $1}')"
    [[ -n "$expected" && "$expected" == "$actual" ]] || die "checksum mismatch for $file"
  done <<EOF
KLAB_ROOTFS_SHA256 $out
KLAB_ROOTFS_PACKAGES_SHA256 $dir/packages.tsv
KLAB_ROOTFS_REPOSITORIES_SHA256 $dir/repositories.tar.zst
EOF
  zstd -tq "$out"; zstd -tq "$dir/repositories.tar.zst"
  printf 'PASS native:%s:%s:%s %s\n' "$provider" "$release" "$arch" "$(sha256sum "$out" | awk '{print $1}')"
}

status() {
  local provider release arch dir state sha
  provider="$(normalize_provider "$1")"; release="$2"; arch="$(canonical_arch "$3")"
  dir="$(artifact_dir "$provider" "$release" "$arch")"; state=missing; sha=-
  if [[ -s "$dir/rootfs.tar.zst" && -s "$dir/metadata.env" ]]; then
    state=ready; sha="$(sha256sum "$dir/rootfs.tar.zst" | awk '{print $1}')"
  fi
  printf 'PROVIDER\tRELEASE\tARCH\tSTATE\tSHA256\tPATH\n'
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$provider" "$release" "$arch" "$state" "$sha" "$dir/rootfs.tar.zst"
}

case "${1:-}" in
  capture) [[ $# -ge 3 && $# -le 4 ]] || die 'capture PROVIDER RELEASE [ARCH]'; capture "$2" "$3" "${4:-$ARCH}" ;;
  verify) [[ $# -ge 3 && $# -le 4 ]] || die 'verify PROVIDER RELEASE [ARCH]'; verify "$2" "$3" "${4:-$ARCH}" ;;
  status) [[ $# -ge 3 && $# -le 4 ]] || die 'status PROVIDER RELEASE [ARCH]'; status "$2" "$3" "${4:-$ARCH}" ;;
  *) die 'usage: klab-native-rootfs.sh capture|verify|status PROVIDER RELEASE [ARCH]' ;;
esac
