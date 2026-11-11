#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

bash -n "$ROOT/klab-native-rootfs.sh" "$ROOT/kernel-lab.sh"
grep -Fq 'native-oci-export-tar-zstd-v1' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'native:ubuntu:*|native:debian:*|native:fedora:*|native:centos:*|native:alpine:*' "$ROOT/kernel-lab.sh"
grep -Fq 'native userspace release' "$ROOT/kernel-lab.sh"
grep -Fq 'packages.tsv' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'repositories.tar.zst' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'curl tar' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'trap cleanup_capture EXIT' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'then pm=dnf; else pm=yum' "$ROOT/klab-native-rootfs.sh"
grep -Fq '[ ! -d /etc/dnf ]' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'apt-cache policy systemd-sysv' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'old-releases.ubuntu.com/ubuntu' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'iproute_package=iproute' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'kmod_package=module-init-tools' "$ROOT/klab-native-rootfs.sh"
grep -Fq "image inspect --format '{{.Architecture}}'" "$ROOT/klab-native-rootfs.sh"
grep -Fq 'rootless_foreign_capture()' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'apt-get install -y --download-only --no-install-recommends --no-upgrade' "$ROOT/klab-native-rootfs.sh"
grep -Fq -- '--no-upgrade $init_package openssh-server' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'gcc make libc6-dev python3' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'tar --keep-directory-symlink -xf - -C "$root"' "$ROOT/klab-native-rootfs.sh"
grep -Fq "grep -q '^sshd:' \"\$root/etc/passwd\"" "$ROOT/klab-native-rootfs.sh"
grep -Fq 'KLAB_ROOTFS_CAPTURE_MODE=rootless-qemu-proot-payload-v1' "$ROOT/klab-native-rootfs.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/store/ubuntu/24.04/x86_64"
cat > "$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "image inspect --format {{.Architecture}} ubuntu:24.04") echo amd64 ;;
  "create --platform linux/amd64 ubuntu:24.04 /bin/sh -ec "*) echo cid-test ;;
  "start cid-test") echo cid-test ;;
  "exec cid-test test -f /tmp/klab-native-ready") exit 0 ;;
  "exec cid-test /bin/sh -ec dpkg-query"*) printf 'base-files\t1\tamd64\n' ;;
  "exec cid-test /bin/sh -ec tar -C / -cf - etc/apt 2>/dev/null")
    [[ "${KLAB_TEST_FAIL_REPO:-0}" != 1 ]] || exit 127
    tar -cf - --files-from /dev/null
    ;;
  "export cid-test") tar -cf - --files-from /dev/null ;;
  "image inspect --format {{.Id}} ubuntu:24.04") echo sha256:image ;;
  "image inspect --format {{join .RepoDigests \",\"}} ubuntu:24.04") echo ubuntu@sha256:digest ;;
  "image inspect --format {{.Created}} ubuntu:24.04") echo 2026-01-01T00:00:00Z ;;
  "rm -f cid-test") [[ -z "${KLAB_TEST_CLEANUP_MARKER:-}" ]] || : >"$KLAB_TEST_CLEANUP_MARKER"; exit 0 ;;
  *) echo "unexpected docker call: $*" >&2; exit 99 ;;
esac
EOF
chmod +x "$tmp/bin/docker"
KLAB_NATIVE_ROOTFS_STORE="$tmp/store" KLAB_CONTAINER_RUNTIME="$tmp/bin/docker" "$ROOT/klab-native-rootfs.sh" capture ubuntu 24.04 x86_64 >/dev/null
KLAB_NATIVE_ROOTFS_STORE="$tmp/store" "$ROOT/klab-native-rootfs.sh" verify ubuntu 24.04 x86_64 | grep -Fq 'PASS native:ubuntu:24.04:x86_64'
grep -Fq 'KLAB_ROOTFS_IMAGE_DIGESTS=ubuntu@sha256:digest' "$tmp/store/ubuntu/24.04/x86_64/metadata.env"

set +e
KLAB_TEST_FAIL_REPO=1 KLAB_TEST_CLEANUP_MARKER="$tmp/cleaned" KLAB_NATIVE_ROOTFS_STORE="$tmp/fail-store" KLAB_CONTAINER_RUNTIME="$tmp/bin/docker" "$ROOT/klab-native-rootfs.sh" capture ubuntu 24.04 x86_64 >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 && -f "$tmp/cleaned" ]] || { echo 'FAIL: failed native capture did not remove its container' >&2; exit 1; }
echo 'PASS: provider-qualified native rootfs capture, provenance, inventory, and checksum model'
grep -Fq "quay.io/centos/centos:%s" "$ROOT/klab-native-rootfs.sh"
grep -Fq 'baseurl=https://vault.centos.org/7.9.2009' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'curl_package=curl-minimal' "$ROOT/klab-native-rootfs.sh"
grep -Fq 'snapshot.debian.org' "$ROOT/klab-native-rootfs.sh"
grep -Fq '"$RUNTIME" logs "$cid"' "$ROOT/klab-native-rootfs.sh"
