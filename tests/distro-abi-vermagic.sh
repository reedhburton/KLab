#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for f in "$ROOT/lib/buildenv-capture.sh" "$ROOT/lib/backends/apt.sh" "$ROOT/lib/backends/rpm.sh"; do
  grep -q 'modinfo -F vermagic' "$f"
  ! grep -q 'kernelrelease mismatch' "$f"
done
grep -Fq 'pr_info("kernel_lab_hello: loaded\n")' "$ROOT/kernel-lab.sh"
grep -Fq 'while ! dmesg | grep -q ' "$ROOT/kernel-lab.sh"
grep -Fq '[ "$i" -lt 5 ] || exit 1' "$ROOT/kernel-lab.sh"
grep -Fq 'dmesg -n 1 2>/dev/null || true' "$ROOT/kernel-lab.sh"
grep -Fq "grep -q '^KLAB_RESULT=PASS'" "$ROOT/kernel-lab.sh"
! grep -Fq "grep -q '^KLAB_RESULT=PASS$'" "$ROOT/kernel-lab.sh"
echo "PASS: distro ABI identity uses module vermagic, not upstream Makefile base"
