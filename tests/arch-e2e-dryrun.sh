#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export KLAB_ROOT="$T/lab"

check_arch(){
  local arch="$1" qemu="$2" bits="$3" out report
  out="$($ROOT/kernel-lab.sh arch-smoke upstream:v6.6 --arch "$arch" --dry-run)"
  printf '%s\n' "$out" | grep -q "^arch=$arch$" || { echo "FAIL: dry-run missing $arch" >&2; exit 1; }
  report="$(printf '%s\n' "$out" | sed -n 's/^report=//p')"
  [[ -f "$report/report.json" ]] || { echo "FAIL: $arch dry-run report.json missing" >&2; exit 1; }
  python3 - "$report/report.json" "$arch" "$qemu" "$bits" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); arch,qemu,bits=sys.argv[2:]
assert m['schema']=='klab-arch-e2e-v2'
assert m['result']=='PASS'
a=m['architecture_plan']
assert a['target_arch']==arch
assert a['toolchain_target_arch']==arch
assert a['guest_arch']==arch
assert a['execution']['qemu_binary']==qemu
assert a['execution']['e2e_status']=='stable'
assert a['execution']['control_mode'] in ('serial','virtio-serial')
assert a['profile']['bits']==int(bits)
PY
}

check_arch x86_64 qemu-system-x86_64 64
check_arch i386 qemu-system-i386 32
check_arch aarch64 qemu-system-aarch64 64
check_arch armv7 qemu-system-arm 32

if "$ROOT/kernel-lab.sh" arch-smoke upstream:v3.6 --arch aarch64 --dry-run >/dev/null 2>&1; then
  echo 'FAIL: aarch64 arch-smoke accepted pre-3.7 Linux' >&2; exit 1
fi
# Model-only MIPS profiles must not silently become E2E supported.
if KLAB_ENABLE_EXPERIMENTAL_ARCHES=1 "$ROOT/kernel-lab.sh" arch-smoke upstream:v6.6 --arch mipsel --dry-run >/dev/null 2>&1; then
  echo 'FAIL: experimental mipsel E2E was accepted without explicit E2E enablement' >&2; exit 1
fi
# A non-dry-run must fail in preflight before network/build work when QEMU is absent.
set +e
KLAB_QEMU=/definitely/not/a/qemu "$ROOT/kernel-lab.sh" arch-smoke upstream:v6.6 --arch armv7 >/dev/null 2>"$T/fail.log"
rc=$?
set -e
(( rc != 0 )) || { echo 'FAIL: missing QEMU was accepted' >&2; exit 1; }
failure_report="$(find "$KLAB_ROOT/results/arch-e2e" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
[[ -f "$failure_report/report.json" ]] || { echo 'FAIL: failure report missing' >&2; exit 1; }
python3 - "$failure_report/report.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); assert m['result']=='FAIL'; assert m['last_stage']=='preflight'; assert m['target_arch']=='armv7'
PY

echo 'PASS: multi-architecture E2E dry-run/fail-report contract'
