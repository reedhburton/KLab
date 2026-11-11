#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
usage(){ echo "usage: bsd-module-smoke.sh TARGET REPO ROOT" >&2; exit 2; }
[[ $# == 3 ]] || usage
target="$1"; repo="$2"; root="$3"; safe="$(printf %s "$target" | tr '/:' '__')"
dest="$repo/bsd/$safe"; env_file="$dest/target.env"
[[ -f "$env_file" ]] || { echo "klab: target absent: $target" >&2; exit 2; }
# shellcheck disable=SC1090
source "$env_file"
[[ "$TARGET" == "$target" ]] || exit 2
sources="$repo/bsd/sources"; "$SELF/bsd/prepare-module-sources.sh" "$target" "$repo" >/dev/null; result="$root/results/bsd/$safe/module"
mkdir -p "$result"; fixture="$(mktemp /tmp/klab-bsd-module.XXXXXX.tgz)"; trap 'rm -f "$fixture"' EXIT
harness=(python3 "$SELF/bsd/native-ssh-smoke.py")
case "$target" in
  netbsd:11.0:x86_64|netbsd:11.0:aarch64|netbsd:11.0:i386)
    iso="$sources/netbsd-11.0-syssrc.iso"
    (cd "$sources" && sha256sum -c netbsd-11.0-syssrc.iso.sha256 >/dev/null) || { echo "klab: missing or invalid NetBSD 11.0 source ISO: $iso" >&2; exit 2; }
    tar -C "$SELF/tests/bsd-modules/netbsd" -czf "$fixture" .
    arch="${target##*:}"; format=raw; disk="$dest/$MEDIA"; password=()
    [[ "$arch" != i386 ]] || { format=qcow2; disk="$dest/$DERIVED_MEDIA"; password=(--password 'KLabRoot7!'); }
    [[ "$arch" != aarch64 ]] || password=(--netbsd-single-user)
    command="/bin/sh -c 'set -eux; mkdir -p /mnt/src; mounted=0; for d in /dev/cd0a /dev/ld1a /dev/ld1 /dev/ld5a /dev/ld5d /dev/ld5; do /sbin/mount -t cd9660 \$d /mnt/src 2>/dev/null && mounted=1 && break; done; test \$mounted = 1; rm -rf /tmp/klab-module; mkdir /tmp/klab-module; tar -xzf /tmp/klab-module.tgz -C /tmp/klab-module; cd /tmp/klab-module; make S=/mnt/src/usr/src/sys NETBSDSRCDIR=/mnt/src/usr/src; test -s klab_hello.kmod; /sbin/modload ./klab_hello.kmod; /sbin/modstat | grep klab_hello; /sbin/dmesg | grep KLAB_NETBSD_MODULE_LOADED; /sbin/modunload klab_hello; /sbin/dmesg | grep KLAB_NETBSD_MODULE_UNLOADED; echo KLAB_NETBSD_MODULE_PASS'"
    "${harness[@]}" --family netbsd --arch "$arch" --disk "$disk" --format "$format" "${password[@]}" --cdrom "$iso" --log "$result/module.log" --upload "$fixture:/tmp/klab-module.tgz" --remote-command "$command" --expect KLAB_NETBSD_MODULE_PASS
    ;;
  dragonfly:6.2.2:x86_64|dragonfly:6.4.2:x86_64)
    version="${target#*:}"; version="${version%%:*}"; iso="$sources/dragonfly-v${version}-src.iso"
    case "$version" in
      6.2.2) expected=02a40051b2b1c20bb305aaa0d96c43478b2ee6302bceaa0da47309133b4e05a7; srcroot=DragonFlyBSD-6.2.2;;
      6.4.2) expected=f6835b43913ca0e1e8e47cc6a618b7a505d5306cfa85c9ec2399170d857e0560; srcroot=DragonFlyBSD-6.4.2;;
    esac
    (cd "$sources" && sha256sum -c "dragonfly-v${version}-src.iso.sha256" >/dev/null) || { echo "klab: missing or invalid DragonFly source ISO: $iso" >&2; exit 2; }
    tar -C "$SELF/tests/bsd-modules/dragonfly" -czf "$fixture" .
    command="/bin/sh -c 'set -eux; mkdir -p /mnt/src; mounted=0; for d in /dev/acd0 /dev/cd0 /dev/cd0a; do /sbin/mount_cd9660 \$d /mnt/src 2>/dev/null && mounted=1 && break; done; test \$mounted = 1; rm -rf /tmp/klab-module; mkdir /tmp/klab-module; tar -xzf /tmp/klab-module.tgz -C /tmp/klab-module; cd /tmp/klab-module; make SYSDIR=/mnt/src/$srcroot/sys; test -s klab_hello.ko; /sbin/kldload -v ./klab_hello.ko; /sbin/kldstat -n klab_hello; /sbin/dmesg | grep KLAB_DRAGONFLY_MODULE_LOADED; /sbin/kldunload -v klab_hello; /sbin/dmesg | grep KLAB_DRAGONFLY_MODULE_UNLOADED; echo KLAB_DRAGONFLY_MODULE_PASS'"
    "${harness[@]}" --family dragonfly --arch x86_64 --disk "$dest/$MEDIA" --format raw --cdrom "$iso" --log "$result/module.log" --upload "$fixture:/tmp/klab-module.tgz" --remote-command "$command" --expect KLAB_DRAGONFLY_MODULE_PASS
    ;;
  *) echo "klab: native module smoke is unsupported for $target" >&2; exit 2;;
esac
printf 'BSD module evidence: %s\n' "$result"
