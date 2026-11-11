#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
export KLAB_ARCH_PROFILES_DIR="$ROOT/architectures"
# shellcheck source=lib/arch-model.sh
source "$ROOT/lib/arch-model.sh"
die(){ echo "FAIL: $*" >&2; exit 1; }

[[ "$(klab_arch_canonical amd64)" == x86_64 ]] || die 'amd64 canonicalization'
[[ "$(klab_arch_canonical arm64)" == aarch64 ]] || die 'arm64 canonicalization'
[[ "$(klab_arch_canonical mips64le)" == mips64el ]] || die 'mips64le canonicalization'
[[ "$(klab_arch_bits aarch64)" == 64 ]] || die 'aarch64 bits'
[[ "$(klab_arch_endian mips)" == big ]] || die 'mips endianness'
[[ "$(klab_arch_endian mipsel)" == little ]] || die 'mipsel endianness'
[[ "$(klab_arch_kernel_arch mips64el)" == mips ]] || die 'mips Linux ARCH mapping'
[[ "$(klab_arch_status mipsel)" == experimental ]] || die 'mipsel status'

klab_arch_kernel_supported aarch64 v3.7 || die 'arm64 must support Linux 3.7'
if klab_arch_kernel_supported aarch64 v3.6.11; then die 'arm64 must reject pre-3.7 Linux'; fi
klab_arch_kernel_supported x86_64 v3.0 || die 'x86_64 Linux 3.0 should be model-valid'

plan="$(KLAB_BUILD_ARCH_OVERRIDE=x86_64 klab_arch_plan_json aarch64)"
python3 - "$plan" <<'PY'
import json,sys
m=json.loads(sys.argv[1])
assert m['schema']=='klab-arch-plan-v1'
assert m['target_arch']=='aarch64'
assert m['build_arch']=='x86_64'
assert m['toolchain_exec_arch']=='x86_64'
assert m['toolchain_target_arch']=='aarch64'
assert m['guest_arch']=='aarch64'
assert m['cross_compile'] is True
assert m['profile']['kernel_arch']=='arm64'
PY

if klab_arch_assert_enabled mipsel; then die 'experimental MIPS should require opt-in'; fi
KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 klab_arch_assert_enabled mipsel || die 'experimental MIPS opt-in failed'

echo 'PASS: architecture target/build/exec/guest model'
