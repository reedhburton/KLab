#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$ROOT/klab-guest-conformance.sh"
grep -Fq 'CAPABILITY\tRESULT\tEVIDENCE' "$ROOT/klab-guest-conformance.sh"
for capability in identity filesystem proc_sys processes toolchain runtime networking modules shutdown_path; do
  grep -Fq "probe $capability " "$ROOT/klab-guest-conformance.sh"
done
grep -Fq 'A boot alone does not qualify' "$ROOT/NATIVE-GUEST-CONTRACT.md"
echo 'PASS: native guest conformance contract and graded probe model'
grep -Fq 'cread clocal -crtscts' "$ROOT/kernel-lab.sh"
grep -Fq 'cp -a "$BUNDLE_MODULES_DIR" "$root/lib/modules/$BUNDLE_KERNEL_RELEASE"' "$ROOT/kernel-lab.sh"
grep -Fq 'NATIVE_MEMORY="${KLAB_NATIVE_MEMORY:-8192M}"' "$ROOT/kernel-lab.sh"
[[ "$(grep -Fc '[[ "$ACTIVE_USERSPACE_SPEC" == native:* ]] && qmem="$NATIVE_MEMORY"' "$ROOT/kernel-lab.sh")" == 2 ]]
grep -Fq '/usr/sbin/sshd -D -e' "$ROOT/kernel-lab.sh"
grep -Fq 'if [[ -d "$root" ]]; then chmod -R u+w "$root"' "$ROOT/kernel-lab.sh"
grep -Fq 'if [[ ! -s "$root/lib/modules/$BUNDLE_KERNEL_RELEASE/modules.dep" ]]' "$ROOT/kernel-lab.sh"
