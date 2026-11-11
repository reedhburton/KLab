#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB_BIN="${KLAB_RUNNER:-$SELF/kernel-lab.sh}"
KLAB_ROOT="${KLAB_ROOT:-$HOME/klab-data}"; export KLAB_ROOT
[[ $# -eq 3 ]] || { echo 'usage: klab-image-tcp-gate.sh TARGET ARCH REPORT_DIR' >&2; exit 2; }
target="$1"; arch="$2"; report="$3"; mkdir -p "$report"
tag="$(printf '%s-%s-%s' "$target" "$arch" "$$" | sha256sum | cut -c1-10)"
a="valnet-a-$tag"; b="valnet-b-$tag"; aip=10.77.41.11; bip=10.77.41.12
port=$((25000 + ($$ % 10000))); bus="230.77.41.1:$port"; binary="$report/network-pair"
cleanup() {
  local n root
  for n in "$a" "$b"; do
    timeout 90 "$KLAB_BIN" stop "$n" >>"$report/cleanup.log" 2>&1 || true
    root="$KLAB_ROOT/work/initramfs/session_${n}.session.root"
    [[ ! -d "$root" ]] || chmod -R u+w "$root" 2>/dev/null || true
    rm -rf "$root" "$KLAB_ROOT/work/initramfs/session_${n}.session.cpio.gz" "$KLAB_ROOT/work/sessions/$n" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM
net_userspace=buildroot:minimal
if [[ "$arch" == i386 && ( "$target" == upstream:v2.0.40 || "$target" == upstream:v2.2.26 ) ]]; then
  net_userspace=busybox-static
  gcc -m32 -Os -nostdlib -static -fno-pie -no-pie -fno-stack-protector -Wl,-e,_start -Wl,--build-id=none -o "$binary" "$SELF/legacy/network-pair-linux22.c" >"$report/build.log" 2>&1
else
  "$KLAB_BIN" build-user "$target" --arch "$arch" --userspace buildroot:minimal --source "$SELF/examples/network-pair.c" -o "$binary" >"$report/build.log" 2>&1
fi
"$KLAB_BIN" boot "$target" --arch "$arch" --userspace "$net_userspace" --name "$a" --net-bus "$bus" --net-ip "$aip/24" --net-mac 52:54:00:41:00:11 --preload "$binary" /tmp/network-pair >"$report/server-boot.log" 2>&1
"$KLAB_BIN" boot "$target" --arch "$arch" --userspace "$net_userspace" --name "$b" --net-bus "$bus" --net-ip "$bip/24" --net-mac 52:54:00:41:00:12 --preload "$binary" /tmp/network-pair >"$report/client-boot.log" 2>&1
"$KLAB_BIN" exec "$a" 'chmod 755 /tmp/network-pair; /tmp/network-pair server 23456 1 >/tmp/klab-tcp-server.log 2>&1 & echo $!' >"$report/server-start.log" 2>&1
"$KLAB_BIN" exec "$b" "chmod 755 /tmp/network-pair; /tmp/network-pair client $aip 23456 klab-image-validation" >"$report/client.log" 2>&1
"$KLAB_BIN" exec "$a" "i=0; while ! grep -q SERVER_DONE /tmp/klab-tcp-server.log && [ \$i -lt 50 ]; do i=\$(expr "\$i" + 1); sleep 0.1; done; cat /tmp/klab-tcp-server.log; grep -q 'SERVER_RX klab-image-validation' /tmp/klab-tcp-server.log; grep -q SERVER_DONE /tmp/klab-tcp-server.log" >"$report/server.log" 2>&1
grep -q 'CLIENT_RX ACK:klab-image-validation' "$report/client.log"
printf 'KLAB_TWO_GUEST_TCP_PASS target=%s arch=%s server=%s client=%s\n' "$target" "$arch" "$aip" "$bip" | tee "$report/PASS"
