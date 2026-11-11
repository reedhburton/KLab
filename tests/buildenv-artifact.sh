#!/usr/bin/env bash
set -Eeuo pipefail
unset KLAB_HOME
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null || true; rm -rf "$T"' EXIT
mkdir -p "$T/root/usr/src/linux-test/scripts" "$T/root/bin" "$T/root/etc"
printf 'all:\n\t@:\n' >"$T/root/usr/src/linux-test/Makefile"
printf '# synthetic\n' >"$T/root/usr/src/linux-test/scripts/Makefile.build"
printf 'pkg-a 1 x86_64 abc\n' >"$T/packages.txt"
printf 'pkg\t1\tx86_64\n' >"$T/installed.tsv"
out="$T/test.klabbuildenv"
"$ROOT/klab-buildenv.sh" create --root "$T/root" --provider test --release 1 --kernel-release test-kernel --target-arch x86_64 --exec-arch x86_64 --provider-image sha256:1111111111111111111111111111111111111111111111111111111111111111 --recipe-version test-v1 --build-dir usr/src/linux-test --package-manifest "$T/packages.txt" --installed-inventory "$T/installed.tsv" -o "$out" >/dev/null
id="$("$ROOT/klab-buildenv.sh" verify "$out" --deep)"
KLAB_ROOT="$T/home" "$ROOT/klab-buildenv.sh" import "$out" >/dev/null
KLAB_ROOT="$T/home" "$ROOT/klab-buildenv.sh" verify-installed "$id" >/dev/null
KLAB_ROOT="$T/home" "$ROOT/klab-buildenv.sh" assert-installed "$id" --provider test --release 1 --kernel-release test-kernel --target-arch x86_64 >/dev/null
if KLAB_ROOT="$T/home" "$ROOT/klab-buildenv.sh" assert-installed "$id" --provider test --release 1 --kernel-release wrong-kernel --target-arch x86_64 >/dev/null 2>&1; then
  echo 'FAIL: installed buildenv accepted wrong target identity' >&2; exit 1
fi
printf 'tamper\n' >>"$T/home/artifacts/buildenvs/sha256/$id/root/etc/tampered"
if KLAB_ROOT="$T/home" "$ROOT/klab-buildenv.sh" verify-installed "$id" >/dev/null 2>&1; then echo 'FAIL: installed tamper not detected' >&2; exit 1; fi
printf 'pkg-b 2 x86_64 def\n' >"$T/packages2.txt"
out2="$T/test2.klabbuildenv"
"$ROOT/klab-buildenv.sh" create --root "$T/root" --provider test --release 1 --kernel-release test-kernel --target-arch x86_64 --exec-arch x86_64 --provider-image sha256:1111111111111111111111111111111111111111111111111111111111111111 --recipe-version test-v1 --build-dir usr/src/linux-test --package-manifest "$T/packages2.txt" --installed-inventory "$T/installed.tsv" -o "$out2" >/dev/null
id2="$("$ROOT/klab-buildenv.sh" verify "$out2")"; [[ "$id" != "$id2" ]] || { echo 'FAIL: package manifest did not alter identity' >&2; exit 1; }
printf 'pkg\t2\tx86_64\n' >"$T/installed2.tsv"
out3="$T/test3.klabbuildenv"
"$ROOT/klab-buildenv.sh" create --root "$T/root" --provider test --release 1 --kernel-release test-kernel --target-arch x86_64 --exec-arch x86_64 --provider-image sha256:1111111111111111111111111111111111111111111111111111111111111111 --recipe-version test-v1 --build-dir usr/src/linux-test --package-manifest "$T/packages2.txt" --installed-inventory "$T/installed2.tsv" -o "$out3" >/dev/null
id3="$("$ROOT/klab-buildenv.sh" verify "$out3")"; [[ "$id2" != "$id3" ]] || { echo 'FAIL: installed package inventory did not alter identity' >&2; exit 1; }
echo 'buildenv-artifact: PASS'

for legacy in builds logs kernels toolchains guests buildenvs distro-toolchains objects MODE; do
  [[ ! -e "$T/home/$legacy" && ! -L "$T/home/$legacy" ]] || { echo "legacy path created: $legacy" >&2; exit 1; }
done
