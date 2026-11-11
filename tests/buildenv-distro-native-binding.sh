#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/root/usr/src/k/scripts" "$t/root/var/lib/klab" "$t/root/bin" "$t/root/usr/bin"; : >"$t/root/usr/src/k/Makefile"; : >"$t/root/usr/src/k/scripts/Makefile.build"
: >"$t/root/var/lib/klab/host-tool-owners.tsv"
for tool in /bin/sh /usr/bin/make awk sed grep find xargs basename dirname tr cut sort head mkdir rm cp mv ln cat; do
  case "$tool" in /*) path="$tool";; *) path="/usr/bin/$tool";; esac
  mkdir -p "$t/root/$(dirname "${path#/}")"; printf '#!/bin/sh\nexit 0\n' >"$t/root/${path#/}"; chmod +x "$t/root/${path#/}"
  printf '%s\t%s\tbasepkg\n' "$tool" "$path" >>"$t/root/var/lib/klab/host-tool-owners.tsv"
done
printf 'x  x\n' >"$t/pkgs.sha"; printf 'basepkg\t1\tamd64\ngcc\t1\tamd64\n' >"$t/inv.tsv"; dtid="$(printf d%.0s {1..64})"
line="$($ROOT/klab-buildenv.sh create --root "$t/root" --provider ubuntu --release old --kernel-release 1.0-old --target-arch x86_64 --exec-arch x86_64 --provider-image sha256:$(printf a%.0s {1..64}) --build-dir usr/src/k --package-manifest "$t/pkgs.sha" --installed-inventory "$t/inv.tsv" --compiler-contract distro-native-v1 --distro-toolchain-id "$dtid" -o "$t/a.klabbuildenv")"
id="${line%% *}"; KLAB_HOME="$t/home" "$ROOT/klab-buildenv.sh" import "$t/a.klabbuildenv" >/dev/null
j="$(KLAB_HOME="$t/home" "$ROOT/klab-buildenv.sh" assert-installed "$id" --compiler-contract distro-native-v1 --distro-toolchain-id "$dtid" --json)"
python3 - "$j" "$dtid" <<'PY'
import json,sys
m=json.loads(sys.argv[1]); assert m['compiler_contract']=='distro-native-v1'; assert m['distro_toolchain_id']==sys.argv[2]; assert not m['toolchain_tree_sha256']
PY
if "$ROOT/klab-buildenv.sh" create --root "$t/root" --provider ubuntu --release old --kernel-release 1.0-old --target-arch x86_64 --exec-arch x86_64 --provider-image sha256:$(printf a%.0s {1..64}) --build-dir usr/src/k --package-manifest "$t/pkgs.sha" --installed-inventory "$t/inv.tsv" --compiler-contract gcc-v1 --distro-toolchain-id "$dtid" -o "$t/bad.klabbuildenv" >/dev/null 2>&1; then echo 'FAIL: gcc-v1 accepted distro toolchain binding' >&2; exit 1; fi
echo 'PASS: buildenv identity pins distro-native compiler contract and distro-toolchain object ID'
