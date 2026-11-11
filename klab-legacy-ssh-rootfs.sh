#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source "$SELF/lib/klab-root.sh"
klab_root_ensure_layout
CACHE="$KLAB_CACHE/legacy-ssh/linux20-i386"
OUT="$KLAB_USERSPACE_STORE/legacy-ssh/linux20-glibc21-dropbear044/i386"
mkdir -p "$CACHE" "$OUT"
die(){ echo "klab-legacy-ssh: ERROR: $*" >&2; exit 1; }
fetch(){ local name="$1" sha="$2" url="$3"; local p="$CACHE/$name"; [[ -f "$p" ]] || curl -fsSL "$url" -o "$p"; [[ "$(sha256sum "$p" | awk '{print $1}')" == "$sha" ]] || die "checksum mismatch: $name"; }
fetch_all(){
 fetch dropbear.deb c8331f54028f6c55036319b0873ee572273a6798a0ab8c06a6440120df20d46f https://matt.ucc.asn.au/dropbear/releases/dropbear_0.44+final-1_i386.deb
 fetch busybox.deb 0d3de6256698bdc7c97dd4215c26008ecab35ebdbe3d61b87cd2afb484a4c503 https://archive.debian.org/debian/pool/main/b/busybox/busybox-static_0.60.2-3.1_i386.deb
 fetch libc6.deb 3c9f2dbaa857a6d96febad47976eb8d37ddd886be1bdefd1b1ce463accc10ceb https://archive.debian.org/debian/pool/main/g/glibc/libc6_2.1.3-25_i386.deb
 fetch zlib1g.deb 55fd2bb79546132e5a35e1714a0add21f3ffa63dfae5ed34df0f1a174af531a7 https://archive.debian.org/debian/pool/main/z/zlib/zlib1g_1.1.4-1.0woody0_i386.deb
 fetch sash-slink.deb fce342da53ef1c56e2791a4cd50d2a6ea82ae71bc4748d1995416686c16c736f https://archive.debian.org/debian/dists/slink/main/binary-i386/shells/sash_2.1-5.deb
 fetch netbase-slink.deb 7b18c37a9a6c7109429ea7d3a1878d9059a557fa6504cd1ce5f15e6005ed736d https://archive.debian.org/debian/dists/slink/main/binary-i386/base/netbase_3.11-1.2.deb
 fetch libc6-slink.deb d302925da554c8fb06ca60e5c9edfd7db062c53f829c2577e6015f3902a9f34c https://archive.debian.org/debian/dists/slink/main/binary-i386/base/libc6_2.0.7.19981211-6.deb
}
build(){
 fetch_all; local root; root="$(mktemp -d)"; trap "rm -rf '$root'" EXIT
 for p in busybox libc6 zlib1g dropbear sash-slink netbase-slink; do dpkg-deb -x "$CACHE/$p.deb" "$root"; done
 oldlib="$(mktemp -d)"; dpkg-deb -x "$CACHE/libc6-slink.deb" "$oldlib"
 mkdir -p "$root/lib20"; cp -a "$oldlib/lib/." "$root/lib20/"; rm -rf "$oldlib"
 mkdir -p "$root"/{dev,proc,tmp,var/run/dropbear,root/.ssh,etc/dropbear,sbin,usr/bin,usr/sbin}
 for x in '[' sh ash cat chmod chown echo grep hostname id ifconfig ln mkdir mknod mount ping ps route sleep stty sync touch uname; do ln -sfn busybox "$root/bin/$x"; done
 ln -sfn ../bin/busybox "$root/sbin/init"
 cat > "$root/etc/passwd" <<'EOP'
root:x:0:0:root:/root:/bin/sash
EOP
printf '%s\n' /bin/sash > "$root/etc/shells"
 cat > "$root/etc/group" <<'EOG'
root:x:0:
EOG
 cat > "$root/etc/shadow" <<'EOS'
root:*:10933:0:99999:7:::
EOS
 cat > "$root/init" <<'EOI'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
mount -t proc proc /proc
hostname klab-legacy
log=/dev/ttyS0
linux20=0
case "$(uname -r)" in 2.0.*) log=/dev/console; linux20=1 ;; esac
ifconfig eth0 10.0.2.15 netmask 255.255.255.0 up
route add default gw 10.0.2.2
ifconfig eth0 >"$log" 2>&1
route >"$log" 2>&1
ping -c 2 10.0.2.2 >"$log" 2>&1
mkdir -p /var/run/dropbear /etc/dropbear /root/.ssh
chmod 700 /root /root/.ssh
[ -s /etc/dropbear/dropbear_rsa_host_key ] || dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1
echo KLAB_LEGACY_SSH_READY >"$log"
/usr/sbin/dropbear -F -E -s -r /etc/dropbear/dropbear_rsa_host_key -p 22 >"$log" 2>&1 &
if [ "$linux20" = 1 ]; then
  while :; do sleep 3600; done
else
  exec /bin/sh </dev/ttyS0 >/dev/ttyS0 2>&1
fi
EOI
 gcc -m32 -Os -nostdlib -static -fno-stack-protector -fno-pie -no-pie \
   -Wl,-e,_start -Wl,--build-id=none -o "$root/init-linux20.bin" "$SELF/legacy/legacy-ssh-init-linux20.c"
 chmod 755 "$root/init" "$root/init-linux20.bin"; chmod 700 "$root/root" "$root/root/.ssh"
 env -u LD_PRELOAD "$root/lib/ld-linux.so.2" --library-path "$root/lib:$root/usr/lib" "$root/usr/bin/dropbearkey" -t rsa -f "$root/etc/dropbear/dropbear_rsa_host_key" >/dev/null
 tar -C "$root" --numeric-owner --owner=0 --group=0 -cf "$OUT/rootfs.tar" .
 sha="$(sha256sum "$OUT/rootfs.tar" | awk '{print $1}')"
 cat > "$OUT/metadata.env" <<EOM
KLAB_LEGACY_SSH_PROFILE=linux20-glibc21-dropbear044
KLAB_LEGACY_SSH_ARCH=i386
KLAB_LEGACY_SSH_KERNEL_FLOOR=2.0.30
KLAB_LEGACY_SSH_BUSYBOX=0.60.2-3.1
KLAB_LEGACY_SSH_SASH=2.1-5
KLAB_LEGACY_SSH_NETBASE=3.11-1.2
KLAB_LEGACY_SSH_LIBC20=2.0.7.19981211-6
KLAB_LEGACY_SSH_GLIBC=2.1.3-25
KLAB_LEGACY_SSH_DROPBEAR=0.44+final-1
KLAB_LEGACY_SSH_ROOTFS_SHA256=$sha
EOM
 echo "$OUT/rootfs.tar"
}
verify(){ local sha; [[ -s "$OUT/rootfs.tar" && -s "$OUT/metadata.env" ]] || die 'profile is absent'; sha="$(sed -n 's/^KLAB_LEGACY_SSH_ROOTFS_SHA256=//p' "$OUT/metadata.env")"; [[ "$(sha256sum "$OUT/rootfs.tar" | awk '{print $1}')" == "$sha" ]] || die 'rootfs checksum mismatch'; tar -tf "$OUT/rootfs.tar" | grep './usr/sbin/dropbear' >/dev/null; echo "PASS $OUT/rootfs.tar $sha"; }
case "${1:-}" in build) build; verify;; verify) verify;; path) echo "$OUT/rootfs.tar";; *) echo "usage: $0 build|verify|path" >&2; exit 2;; esac
