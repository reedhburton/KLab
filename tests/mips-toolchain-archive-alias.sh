#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
source "$ROOT/lib/arch-model.sh"
die(){ echo "$*" >&2; return 1; }
eval "$(sed -n '/^canonical_arch()/,/^}/p' "$ROOT/kernel-lab.sh")"
# Extract the production helper without sourcing the CLI dispatcher.
eval "$(sed -n '/^toolchain_arch_matches()/,/^}/p' "$ROOT/kernel-lab.sh")"
for pair in 'mips mipsel' 'mipsel mips' 'mips64 mips64el' 'mips64el mips64'; do
  set -- $pair; toolchain_arch_matches "$1" "$2" || { echo "FAIL: shared archive rejected: $pair" >&2; exit 1; }
done
for pair in 'mips mips64' 'mipsel mips64el' 'i386 x86_64' 'mips aarch64'; do
  set -- $pair; if toolchain_arch_matches "$1" "$2"; then echo "FAIL: incompatible archive accepted: $pair" >&2; exit 1; fi
done
grep -Fq 'toolchain_arch_matches "${KLAB_TOOLCHAIN_ARCH:-$ARCH}" "$ARCH"' "$ROOT/kernel-lab.sh"
grep -Fq 'toolchain_arch_matches "${KLAB_TOOLCHAIN_ARCH:-x86_64}" "$wanted_arch"' "$ROOT/kernel-lab.sh"
echo 'PASS: endian siblings share the matching kernel.org MIPS compiler archive'
