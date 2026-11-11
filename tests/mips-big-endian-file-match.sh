#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
source "$ROOT/lib/arch-model.sh"
arch_profile_field(){ klab_arch_profile_field "$@"; }
source "$ROOT/lib/arch-e2e.sh"
klab_arch_e2e_file_matches mips 'ELF 32-bit MSB executable, MIPS, MIPS32 rel2 version 1 (SYSV), statically linked'
if klab_arch_e2e_file_matches mips 'ELF 32-bit LSB executable, MIPS, MIPS32 rel2 version 1 (SYSV), statically linked'; then echo 'FAIL: little-endian MIPS accepted as big-endian mips' >&2; exit 1; fi
if klab_arch_e2e_file_matches mips 'ELF 64-bit MSB executable, MIPS, MIPS64 rel2 version 1 (SYSV), statically linked'; then echo 'FAIL: MIPS64 accepted as mips' >&2; exit 1; fi
echo 'PASS: big-endian MIPS ELF validation'
