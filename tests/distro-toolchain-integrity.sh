#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/pkgs"; printf x >"$t/pkgs/gcc.deb"; printf 'gcc\t1.2.3\tamd64\n' >"$t/inv.tsv"
printf '%s\n' '{"cc_path":"/usr/bin/gcc","cc_version":"1.2.3","cc_target":"x86_64-linux-gnu","as_path":"/usr/bin/as","as_version":"2.20","ld_path":"/usr/bin/ld","ld_version":"2.20"}' >"$t/compiler.json"
line="$($ROOT/klab-distro-toolchain.sh create --packages "$t/pkgs" --inventory "$t/inv.tsv" --compiler-json "$t/compiler.json" --provider ubuntu --release old --arch x86_64 -o "$t/good.klabdistrotoolchain")"; id="${line%%$'\t'*}"
KLAB_HOME="$t/home" "$ROOT/klab-distro-toolchain.sh" import "$t/good.klabdistrotoolchain" >/dev/null
printf corrupt >>"$t/home/artifacts/distro-toolchains/sha256/$id/spec/compiler.json"
if KLAB_HOME="$t/home" "$ROOT/klab-distro-toolchain.sh" import "$t/good.klabdistrotoolchain" >/dev/null 2>&1; then echo 'FAIL: corrupt installed object accepted' >&2; exit 1; fi
KLAB_HOME="$t/home" "$ROOT/klab-distro-toolchain.sh" import "$t/good.klabdistrotoolchain" --force >/dev/null
mkdir "$t/x"; tar --zstd -xf "$t/good.klabdistrotoolchain" -C "$t/x"; printf evil >"$t/x/UNTRACKED"; tar -C "$t/x" --zstd -cf "$t/bad.klabdistrotoolchain" .
if "$ROOT/klab-distro-toolchain.sh" verify "$t/bad.klabdistrotoolchain" >/dev/null 2>&1; then echo 'FAIL: unchecksummed extra member accepted' >&2; exit 1; fi
echo 'PASS: distro toolchain rejects corrupt installed objects and unchecksummed archive members'
