#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export KLAB_ROOT="$T/lab"; for pair in 'x86_64 e1000' 'i386 e1000' 'aarch64 virtio-net-device' 'armv7 virtio-net-device'; do set -- $pair; got="$("$ROOT/kernel-lab.sh" arch-plan "$1" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["execution"]["network_device"])')"; [[ "$got" == "$2" ]]; done
for pair in 'mips pcnet' 'mipsel pcnet'; do set -- $pair; got="$(KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 "$ROOT/kernel-lab.sh" arch-plan "$1" --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["execution"]["network_device"])')"; [[ "$got" == "$2" ]]; done
grep -q "SESSION_NET_BUS" "$ROOT/kernel-lab.sh"
grep -q 'LAB_HOME|\$target|\$ARCH|\$profile|\$name' "$ROOT/kernel-lab.sh"
echo PASS

grep -Fq 'wc ifconfig route ping' "$ROOT/kernel-lab.sh"

grep -Fq 'modprobe e1000 2>/dev/null || true' "$ROOT/kernel-lab.sh"
grep -Fq 'modprobe virtio_pci 2>/dev/null || true' "$ROOT/kernel-lab.sh"
grep -Fq 'modprobe virtio_net 2>/dev/null || true' "$ROOT/kernel-lab.sh"
grep -Fq 'qemu_net_device_for_target' "$ROOT/kernel-lab.sh"
grep -Fq 'echo virtio-net-pci' "$ROOT/kernel-lab.sh"
grep -Fq 'bundle_existing_dir_for "$provider" "$release" "$kernel" "$arch"' "$ROOT/kernel-lab.sh"

# iproute2 from a current userspace can return without configuring very old
# kernels; verify IPv4 and fall back to BusyBox ifconfig.
grep -Fq "session_rpc_exec \"\$sock\" '[ -x /bin/ifconfig ] || [ -x /sbin/ifconfig ]'" "$ROOT/kernel-lab.sh"
grep -Fq "ip link set '\$iface' up" "$ROOT/kernel-lab.sh"
grep -Fq "return 45" "$ROOT/kernel-lab.sh"

# Linux through 3.11 cannot safely expose an arbitrary modern host CPU state
# model through KVM; both one-shot and persistent runners use stable TCG.
test "$(grep -F -c '"$target" == upstream:v3.1[01]' "$ROOT/kernel-lab.sh")" -eq 2
# Keep serial RPC requests below old ash/read line limits and resolve a MAC in
# a separate request before configuring and verifying the selected interface.
grep -Fq 'resolved="$(session_rpc_exec "$sock"' "$ROOT/kernel-lab.sh"
grep -Fq 'legacy_config=1' "$ROOT/kernel-lab.sh"
grep -Fq "route add -net '\$network' netmask '\$mask' dev '\$iface'" "$ROOT/kernel-lab.sh"
grep -Fq 'return 45' "$ROOT/kernel-lab.sh"
# Old e1000 drivers need a brief link-settle window after control readiness.
grep -Fq 'legacy_guest_busybox_target "$target" && { ((${#net_ids[@]} > 0)) || [[ "$ssh_auth" != off ]]; }' "$ROOT/kernel-lab.sh"
# The imported 2.6.22 build enumerates its two 8250 ports in reverse order.
grep -Fq '"$target" == upstream:v2.6.22 && "$ARCH" == x86_64' "$ROOT/kernel-lab.sh"
grep -Fq 'session_serial=("${control[@]}" -serial "file:$console")' "$ROOT/kernel-lab.sh"
grep -Fq 'linux_session_control_tty "$ARCH" "$target"' "$ROOT/kernel-lab.sh"
grep -Fq 'console=$(linux_session_console "$ARCH" "$target")' "$ROOT/kernel-lab.sh"
