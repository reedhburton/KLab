#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
source "$ROOT/lib/arch-model.sh"
[[ "$(klab_arch_status mips)" == experimental ]]
[[ "$(klab_arch_e2e_status mips)" == experimental ]]
[[ "$(klab_arch_kernel_defconfig mips)" == malta_defconfig ]]
[[ "$(klab_arch_toolchain_target mips)" == mips-linux ]]
[[ "$(klab_arch_profile_field mips BUILDROOT_DEFCONFIG)" == qemu_mips32r2_malta_defconfig ]]
[[ "$(klab_arch_profile_field mips QEMU_MEMORY)" == 256M ]]
[[ "$(klab_arch_profile_field mips QEMU_CPUS)" == 1 ]]
[[ "$(klab_arch_profile_field mips KERNEL_CONFIG_ENABLE)" == *CPU_BIG_ENDIAN* ]]
[[ "$(klab_arch_profile_field mips KERNEL_CONFIG_DISABLE)" == *CPU_LITTLE_ENDIAN* ]]
plan="$(KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 "$ROOT/kernel-lab.sh" arch-plan mips --build x86_64 --kernel v6.6 --json)"
python3 - "$plan" <<'PY'
import json,sys
p=json.loads(sys.argv[1])
assert p['target_arch']=='mips'
assert p['profile']['endian']=='big'
assert p['profile']['bits']==32
assert p['profile']['abi']=='o32'
assert p['toolchain']['target']=='mips-linux'
assert p['execution']['qemu_binary']=='qemu-system-mips'
assert p['execution']['qemu_machine']=='malta'
assert p['execution']['qemu_memory']=='256M'
assert p['execution']['qemu_cpus']==1
assert p['execution']['e2e_status']=='experimental'
PY
if "$ROOT/kernel-lab.sh" arch-smoke upstream:v6.6 --arch mips --dry-run >/dev/null 2>&1; then
  echo 'FAIL: mips accepted without experimental arch gate' >&2; exit 1
fi
out="$(KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 KLAB_ENABLE_EXPERIMENTAL_E2E=1 "$ROOT/kernel-lab.sh" arch-smoke upstream:v6.6 --arch mips --dry-run)"
grep -q '^arch=mips$' <<<"$out"
grep -q '^qemu=qemu-system-mips$' <<<"$out"
echo 'PASS: big-endian MIPS E2E model'
