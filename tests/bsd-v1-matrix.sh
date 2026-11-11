#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="$(python3 "$ROOT/tools/bsd-v1-status.py")"
grep -q '^BSD_V1_GATE=PASS$' <<<"$OUT"
grep -q '^freebsd-current-amd64.*MODULE_PASS.*MODULE_PASS.*pass$' <<<"$OUT"
grep -q '^freebsd-current-aarch64.*MODULE_PASS.*MODULE_PASS.*pass$' <<<"$OUT"
grep -q '^netbsd-current-i386.*USERSPACE_PASS.*USERSPACE_PASS.*pass$' <<<"$OUT"
grep -q '^openbsd-current-amd64.*USERSPACE_PASS.*USERSPACE_PASS.*pass$' <<<"$OUT"
grep -q '^openbsd-current-arm64.*USERSPACE_PASS.*USERSPACE_PASS.*pass$' <<<"$OUT"
grep -q '^dragonfly-current-x86_64.*USERSPACE_PASS.*USERSPACE_PASS.*pass$' <<<"$OUT"
grep -q '^freebsd-previous-i386.*USERSPACE_PASS.*USERSPACE_PASS.*pass$' <<<"$OUT"
grep -q '^freebsd-previous-riscv64.*USERSPACE_PASS.*USERSPACE_PASS.*pass$' <<<"$OUT"
grep -q '^netbsd-current-aarch64.*USERSPACE_PASS.*USERSPACE_PASS.*pass$' <<<"$OUT"
grep -q '^dragonfly-previous-x86_64.*BOOT_PASS.*USERSPACE_PASS.*pass$' <<<"$OUT"
grep -q 'host-tools/genisoimage/usr/bin/genisoimage' "$ROOT/kernel-lab.sh"
grep -q 'case "${tool##\*/}" in' "$ROOT/kernel-lab.sh"
grep -q 'ISO builder did not create' "$ROOT/kernel-lab.sh"
grep -q 'KLAB_FREEBSD_AARCH64_CPU:-}' "$ROOT/kernel-lab.sh"
grep -q 'KLAB_FREEBSD_AARCH64_MACHINE:-}' "$ROOT/kernel-lab.sh"
grep -q 'failed/panicked prior boot can leave its detached relay' "$ROOT/kernel-lab.sh"
python3 "$ROOT/tools/bsd-v1-status.py" --check >/dev/null
echo 'BSD v1 matrix: PASS (all minimum required targets satisfy the release gate)'
python3 -m py_compile "$ROOT/bsd/netbsd-live-smoke.py"
grep -q 'KLAB_NETBSD_USERSPACE_OK' "$ROOT/bsd/netbsd-live-smoke.py"
python3 -m py_compile "$ROOT/bsd/dragonfly-live-smoke.py"
grep -q 'KLAB_DRAGONFLY_USERSPACE_OK' "$ROOT/bsd/dragonfly-live-smoke.py"
python3 -m py_compile "$ROOT/bsd/openbsd-installer-smoke.py" "$ROOT/bsd/openbsd-installed-smoke.py"
grep -q 'KLAB_OPENBSD_INSTALLER_USERSPACE_OK' "$ROOT/bsd/openbsd-installer-smoke.py"
grep -q 'KLAB_OPENBSD_USERSPACE_OK' "$ROOT/bsd/openbsd-installed-smoke.py"

python3 -m py_compile "$ROOT/bsd/netbsd-i386-installer-smoke.py"
grep -q 'KLAB_NETBSD_I386_INSTALLER_BOOT_OK' "$ROOT/bsd/netbsd-i386-installer-smoke.py"
python3 -m py_compile "$ROOT/bsd/openbsd-arm64-installer-smoke.py"
grep -q 'KLAB_OPENBSD_ARM64_INSTALLER_USERSPACE_OK' "$ROOT/bsd/openbsd-arm64-installer-smoke.py"
python3 -m py_compile "$ROOT/bsd/openbsd-arm64-installed-smoke.py" "$ROOT/bsd/unix-serial-console.py"
grep -q 'KLAB_OPENBSD_ARM64_USERSPACE_OK' "$ROOT/bsd/openbsd-arm64-installed-smoke.py"
python3 -m py_compile "$ROOT/bsd/netbsd-i386-installed-smoke.py"
grep -q 'KLAB_NETBSD_I386_USERSPACE_OK' "$ROOT/bsd/netbsd-i386-installed-smoke.py"
grep -q 'tty=/dev/ttyV0.0' "$ROOT/kernel-lab.sh"
grep -q 'virtserialport,chardev=klabagent' "$ROOT/kernel-lab.sh"
python3 -m py_compile "$ROOT/bsd/freebsd-rpc.py" "$ROOT/bsd/serial-relay.py"
grep -q 'FROM debian:trixie-slim' "$ROOT/containers/qemu10-aarch64.Dockerfile"
python3 -m py_compile "$ROOT/bsd/freebsd-i386-smoke.py" "$ROOT/bsd/freebsd-riscv64-smoke.py" "$ROOT/bsd/netbsd-arm64-smoke.py"
grep -q 'qemu-system-misc qemu-utils opensbi u-boot-qemu' "$ROOT/containers/qemu10-riscv64.Dockerfile"
grep -q 'KLAB_FREEBSD_RISCV64_USERSPACE_OK' "$ROOT/bsd/freebsd-riscv64-smoke.py"
grep -q 'KLAB_FREEBSD_I386_USERSPACE_OK' "$ROOT/bsd/freebsd-i386-smoke.py"
grep -q 'KLAB_NETBSD_ARM64_USERSPACE_OK' "$ROOT/bsd/netbsd-arm64-smoke.py"
bash -n "$ROOT/bsd/bsd-simple.sh"
"$ROOT/bsd/bsd-simple.sh" list | grep -q '^freebsd:14.5-RELEASE:riscv64$'
"$ROOT/bsd/bsd-simple.sh" supports netbsd:11.0:aarch64
"$ROOT/bsd/bsd-simple.sh" supports netbsd:11.0:x86_64
"$ROOT/bsd/bsd-simple.sh" supports netbsd:11.0:i386
"$ROOT/bsd/bsd-simple.sh" supports openbsd:7.9:x86_64
"$ROOT/bsd/bsd-simple.sh" list | grep -q '^openbsd:7.9:x86_64$'
grep -Fq 'fdbdffb1de773a67857e702eb8276701b47a7828f27ea5819ff07a630f64cfd0' "$ROOT/bsd/bsd-simple.sh"
"$ROOT/bsd/bsd-simple.sh" list | grep -q '^netbsd:11.0:i386$'
grep -Fq '5a906a49ebf9a3d1b70581c5790de0a303cf2f1cc6b3d38ce905ad3767b35d1a' "$ROOT/bsd/bsd-simple.sh"
grep -Fq 'requires the verified installed disk' "$ROOT/bsd/bsd-simple.sh"
"$ROOT/bsd/bsd-simple.sh" list | grep -q '^netbsd:11.0:x86_64$'
grep -Fq 'a7aef57bd940bfd1e6d6fd34ba7b6f7459b8ed2084fe219314d345d07eb76a4ac0776b013b34e972c76f431039bf66485bfb94e6260f3ff6d66a811e4c0df55b' "$ROOT/bsd/bsd-simple.sh"
"$ROOT/bsd/bsd-simple.sh" supports dragonfly:6.4.2:x86_64
"$ROOT/bsd/bsd-simple.sh" list | grep -q '^dragonfly:6.4.2:x86_64$'
grep -Fq 'a23812ca816df3de1e3eab5995e29025' "$ROOT/bsd/bsd-simple.sh"
"$ROOT/bsd/bsd-simple.sh" supports openbsd:7.9:aarch64
"$ROOT/bsd/bsd-simple.sh" list | grep -q '^openbsd:7.9:aarch64$'
grep -Fq 'daa123b4b1d7e74ad74473a24e121a0690c434742a68348090c231c7c9dd1eae' "$ROOT/bsd/bsd-simple.sh"
grep -q 'send_slow(serial' "$ROOT/bsd/dragonfly-live-smoke.py"
grep -q 'checksum mismatch' "$ROOT/bsd/bsd-simple.sh"
python3 -m py_compile "$ROOT/bsd/native-ssh-smoke.py"
grep -Fq 'KLAB_BSD_SSH_OK' "$ROOT/bsd/native-ssh-smoke.py"
grep -Fq -- '--ssh' "$ROOT/bsd/freebsd-riscv64-smoke.py"
grep -Fq 'KLAB_FREEBSD_RISCV64_SSH_OK' "$ROOT/bsd/freebsd-riscv64-smoke.py"
grep -Fq 'freebsd:14.5-RELEASE:riscv64)' "$ROOT/bsd/bsd-simple.sh"
grep -Fq "choices=('netbsd','openbsd','freebsd','dragonfly')" "$ROOT/bsd/native-ssh-smoke.py"
grep -Fq 'full|minimal|ssh|module' "$ROOT/bsd/bsd-simple.sh"
grep -Fq 'BSD mode must be full, minimal, ssh, or module' "$ROOT/bsd/bsd-simple.sh"
grep -Fq 'bsd-module-smoke.sh' "$ROOT/bsd/bsd-simple.sh"
grep -Fq 'native-overlay.qcow2' "$ROOT/bsd/bsd-simple.sh"
grep -Fq 'BSD_TARGET [--mode minimal|ssh|full]' "$ROOT/klab"
grep -Fq -- '--mode needs minimal, ssh, or full' "$ROOT/lib/simple-cli.sh"

grep -Fq 'with guest networking' "$ROOT/kernel-lab.sh"
grep -Fq 'restrict=on,hostfwd=tcp:${ssh_bind}:${ssh_port}-10.0.2.15:22' "$ROOT/kernel-lab.sh"
grep -Fq 'dhclient vtnet0' "$ROOT/kernel-lab.sh"
grep -Fq 'PermitRootLogin without-password' "$ROOT/kernel-lab.sh"
grep -Fq 'SESSION_BACKEND=freebsd\nSESSION_ARCH=%q' "$ROOT/kernel-lab.sh"

grep -Fq -- '-netdev user,id=klabnet,restrict=on' "$ROOT/kernel-lab.sh"

grep -Fq 'freebsd_boot_timeout < 180' "$ROOT/kernel-lab.sh"

grep -Fq 'make_freebsd_seed_iso "$dir" "$ARCH" "$ssh_pub"' "$ROOT/kernel-lab.sh"
grep -Fq '/root/.ssh/authorized_keys' "$ROOT/kernel-lab.sh"

grep -Fq "printf '%s\\n' EOF_AGENT" "$ROOT/kernel-lab.sh"

grep -Fq 'stty -f "$TTY" 115200 raw -echo 2>/dev/null' "$ROOT/kernel-lab.sh"
! grep -Fq 'stty -f "$TTY" 115200 raw -echo cread clocal -crtscts' "$ROOT/kernel-lab.sh"

python3 - "$ROOT/kernel-lab.sh" <<'PY_BSD_STTY'
import sys
s=open(sys.argv[1]).read()
assert s.index('exec 3<>"$TTY"', s.index('write_freebsd_agent()')) < s.index('stty -f "$TTY" 115200 raw -echo', s.index('write_freebsd_agent()'))
PY_BSD_STTY

grep -Fq 'ifconfig vtnet0 | grep -q "inet 10.0.2."' "$ROOT/kernel-lab.sh"
! grep -Fq 'route -n get default' "$ROOT/kernel-lab.sh"

! sed -n '/boot_freebsd_session()/,/^}/p' "$ROOT/kernel-lab.sh" | grep -Fq 'session_rpc_put "$proxy" "$ssh_pub"'
grep -Fq "timeout 15 ssh -i \"\$ssh_key\" -p \"\$ssh_port\"" "$ROOT/kernel-lab.sh"

grep -Fq 'KLAB_FREEBSD_SSH_READY' "$ROOT/kernel-lab.sh"
grep -Fq 'failed host SSH login' "$ROOT/kernel-lab.sh"
grep -Fq 'b"KLAB_NETBSD_ARM64_USERSPACE_OK", 60' "$ROOT/bsd/netbsd-arm64-smoke.py"
grep -Fq 'USERSPACE_OK\\n' "$ROOT/bsd/netbsd-arm64-smoke.py"
