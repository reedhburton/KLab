#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
die(){ echo "FAIL: $*" >&2; exit 1; }
source "$ROOT/lib/backends/pacman.sh"
klab_provider_run_container(){ local provider="$1" image="$2" script="${@: -1}"; bash -lc "$script"; }
pacman(){
 case "$1:$2" in
  -Sy:--noconfirm) return 0;;
  -Si:linux) printf 'Version         : 7.2.11.arch1-1\n';;
  -Si:linux-lts) printf 'Version         : 6.18.58-1\n';;
  -Si:linux-zen) printf 'Version         : 7.2.11.zen1-1\n';;
  -Si:linux-hardened) printf 'Version         : 7.2.10.hardened1-3\n';;
  *) return 2;;
 esac
}
export -f pacman
actual="$(klab_backend_pacman_list arch rolling ignored 'pacman -Sy --noconfirm >/dev/null')"
expected=$'6.18.58-1-lts\n7.2.10-hardened1-3-hardened\n7.2.11-arch1-1\n7.2.11-zen1-1-zen'
[[ "$actual" == "$expected" ]] || die "kernel release translation mismatch: $actual"
grep -Fq '"$f" != *.sig' "$ROOT/lib/backends/pacman.sh" || die 'package manifest must exclude detached signatures'
grep -q '\[\[ "$p" == \*.sig \]\] && continue' "$ROOT/lib/backends/pacman.sh" || die 'package extraction must exclude detached signatures'
grep -q 'arch) printf.*archlinux:base' "$ROOT/kernel-lab.sh" || die 'Arch image mapping missing'
echo 'PASS: Arch pacman provider release identities and signature boundary'
