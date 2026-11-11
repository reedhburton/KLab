#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
source "$ROOT/lib/arch-model.sh"

[[ "$(klab_arch_status mipsel)" == experimental ]] || { echo 'FAIL: mipsel arch status' >&2; exit 1; }
[[ "$(klab_arch_e2e_status mipsel)" == experimental ]] || { echo 'FAIL: mipsel E2E status' >&2; exit 1; }
[[ "$(klab_arch_kernel_defconfig mipsel)" == malta_defconfig ]] || { echo 'FAIL: mipsel kernel defconfig' >&2; exit 1; }
[[ "$(klab_arch_toolchain_target mipsel)" == mips-linux ]] || { echo 'FAIL: mipsel kernel.org toolchain target' >&2; exit 1; }
[[ "$(klab_arch_profile_field mipsel BUILDROOT_DEFCONFIG)" == qemu_mips32r2el_malta_defconfig ]] || { echo 'FAIL: mipsel Buildroot defconfig' >&2; exit 1; }
[[ "$(klab_arch_profile_field mipsel QEMU_MEMORY)" == 256M ]] || { echo 'FAIL: mipsel QEMU memory' >&2; exit 1; }
[[ "$(klab_arch_profile_field mipsel QEMU_CPUS)" == 1 ]] || { echo 'FAIL: mipsel QEMU cpus' >&2; exit 1; }

plan="$($ROOT/kernel-lab.sh arch-plan mipsel --build x86_64 --kernel v6.6 --json)"
python3 - "$plan" <<'PY'
import json,sys
p=json.loads(sys.argv[1])
assert p['target_arch']=='mipsel'
assert p['profile']['endian']=='little'
assert p['profile']['bits']==32
assert p['profile']['abi']=='o32'
assert p['toolchain']['target']=='mips-linux'
assert p['execution']['qemu_binary']=='qemu-system-mipsel'
assert p['execution']['qemu_machine']=='malta'
assert p['execution']['qemu_memory']=='256M'
assert p['execution']['qemu_cpus']==1
assert p['execution']['control_mode']=='serial'
assert p['execution']['control_device']=='/dev/ttyS1'
assert p['execution']['e2e_status']=='experimental'
PY

if "$ROOT/kernel-lab.sh" arch-smoke upstream:v6.6 --arch mipsel --dry-run >/dev/null 2>&1; then
  echo 'FAIL: mipsel arch-smoke accepted without experimental opt-in' >&2; exit 1
fi
out="$(KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 KLAB_ENABLE_EXPERIMENTAL_E2E=1 "$ROOT/kernel-lab.sh" arch-smoke upstream:v6.6 --arch mipsel --dry-run)"
grep -q '^arch=mipsel$' <<<"$out" || { echo 'FAIL: mipsel dry-run arch' >&2; exit 1; }
grep -q '^qemu=qemu-system-mipsel$' <<<"$out" || { echo 'FAIL: mipsel dry-run qemu' >&2; exit 1; }
echo 'PASS: mipsel E2E model'
