#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck disable=SC1090
source "$ROOT/lib/arch-model.sh"
arch_profile_field(){ klab_arch_profile_field "$@"; }
# shellcheck disable=SC1090
source "$ROOT/lib/arch-e2e.sh"
klab_arch_e2e_file_matches armv7 'ELF 32-bit LSB executable, ARM, EABI5' || { echo 'FAIL: armv7 ELF rejected' >&2; exit 1; }
if klab_arch_e2e_file_matches armv7 'ELF 64-bit LSB executable, ARM aarch64'; then echo 'FAIL: aarch64 ELF accepted as armv7' >&2; exit 1; fi
klab_arch_e2e_file_matches i386 'ELF 32-bit LSB executable, Intel 80386' || { echo 'FAIL: i386 ELF rejected' >&2; exit 1; }
if klab_arch_e2e_file_matches i386 'ELF 64-bit LSB pie executable, x86-64'; then echo 'FAIL: x86-64 ELF accepted as i386' >&2; exit 1; fi
klab_arch_e2e_file_matches aarch64 'ELF 64-bit LSB executable, ARM aarch64' || { echo 'FAIL: aarch64 ELF rejected' >&2; exit 1; }
echo 'PASS: architecture ELF identity filters'
