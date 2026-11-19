#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"; f="$ROOT/kernel-lab.sh"
grep -Fq 'DROPBEAR_SHA256="${KLAB_DROPBEAR_SHA256:-310a6087952897c182efbe16088fa0c4d07c467e850a22699472137278fabf09}"' "$f"
grep -Fq 'file "$build/dropbearmulti" | grep -Fq '\''statically linked' "$f"
grep -Fq -- "-name '*-buildroot-linux-musl*-gcc'" "$f"
grep -Fq 'install_native_ssh_backend "$root" "$ARCH"' "$f"
grep -Fq 'printf '\''%s\n'\'' dropbear-fallback > "$root/etc/klab-ssh-backend"' "$f"
grep -Fq 'native_ssh_backend="$(cat "$INITRAMFS/$key.session.root/etc/klab-ssh-backend"' "$f"
grep -Fq 'if [[ "$native_ssh_backend" == openssh ]]' "$f"
grep -Fq 'failed to start Dropbear' "$f"
grep -Fq 'chmod 0700 "$root/root"' "$f"
grep -Fq "'root:x:0:0:root:/root:/bin/sh'" "$f"
grep -Fq 'chmod 700 /root /root/.ssh' "$f"
! grep -Fq 'usermod -p x root' "$f"
grep -Fq '[[ "$normalized_ssh_userspace" == buildroot:* || "$normalized_ssh_userspace" == native:* ||' "$f"
grep -Fq '( "$normalized_ssh_userspace" == busybox-static && ( "$target" == upstream:v2.0.40 || "$target" == upstream:v2.2.26 || "$target" == upstream:v2.6.0 ) )' "$f"
grep -Fq 'upstream:v2.0.40|upstream:v2.2.26|upstream:v2.6.0) linux_gate_userspace=busybox-static' "$ROOT/klab-image-validate.sh"
grep -Fq '"$target" == upstream:v2.0.40 || "$target" == upstream:v2.2.26 || "$target" == upstream:v2.6.0' "$ROOT/klab-image-validate.sh"
grep -Fq 'upstream:v2.0.40|upstream:v2.2.26|upstream:v2.6.0) ssh_compat=' "$ROOT/klab-image-validate.sh"
echo 'native Dropbear fallback model: PASS'

# Early 2.6 x86 kernels through 2.6.34 use the sealed i386 2020.81 multicall binary; old
# x86_64 kernels provide IA32 emulation and cannot run current static musl SSH.
grep -Fq 'legacy_dropbear_guest_arch()' "$ROOT/kernel-lab.sh"
grep -Fq 'DROPBEAR_VERSION=2020.81' "$ROOT/kernel-lab.sh"
grep -Fq 'install_native_ssh_backend "$root" "$ARCH" "$target"' "$ROOT/kernel-lab.sh"
# Generic Buildroot Dropbear startup remains under old serial RPC line limits.
grep -Fq 'dropbear-prepare.txt' "$ROOT/kernel-lab.sh"
grep -Fq 'dropbear-keygen.txt' "$ROOT/kernel-lab.sh"
grep -Fq 'Old BusyBox read implementations truncate long serial RPC lines' "$ROOT/kernel-lab.sh"

grep -Fq '"$patch" -le 34' "$ROOT/kernel-lab.sh"
