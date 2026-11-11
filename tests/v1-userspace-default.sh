#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq 'userspace="${KLAB_PREPARE_USERSPACE:-${KLAB_USERSPACE:-auto}}"' "$ROOT/kernel-lab.sh"
grep -Fq 'freebsd:*) userspace=busybox-static ;;' "$ROOT/kernel-lab.sh"
grep -Fq 'upstream:*) if legacy_guest_busybox_target "$requested_target"; then userspace=busybox-static; else userspace=buildroot:minimal; fi ;;' "$ROOT/kernel-lab.sh"
grep -Fq '*) userspace=buildroot:minimal ;;' "$ROOT/kernel-lab.sh"
grep -Fq 'resolved=buildroot:minimal' "$ROOT/kernel-lab.sh"
grep -Fq 'legacy_base64="$(ensure_legacy_base64 "$arch")"' "$ROOT/kernel-lab.sh"
echo 'PASS: V1 defaults modern Linux to Buildroot minimal and guards broken BusyBox RPC'
