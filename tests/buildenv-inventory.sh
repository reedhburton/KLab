#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null || true; rm -rf "$T"' EXIT
mkdir -p "$T/root/usr/src/linux-test/scripts"
printf 'all:\n\t@:\n' >"$T/root/usr/src/linux-test/Makefile"
printf '# synthetic\n' >"$T/root/usr/src/linux-test/scripts/Makefile.build"
printf 'pkg 1 x86_64 deadbeef\n' >"$T/packages.txt"
printf 'pkg\t1\tx86_64\n' >"$T/installed.tsv"
"$ROOT/klab-buildenv.sh" create --root "$T/root" --provider test --release 1 --kernel-release k1 \
  --target-arch x86_64 --exec-arch x86_64 --provider-image sha256:3333333333333333333333333333333333333333333333333333333333333333 --build-dir usr/src/linux-test \
  --package-manifest "$T/packages.txt" --installed-inventory "$T/installed.tsv" -o "$T/a.klabbuildenv" >/dev/null
id="$("$ROOT/klab-buildenv.sh" verify "$T/a.klabbuildenv")"
KLAB_HOME="$T/home" "$ROOT/klab-buildenv.sh" import "$T/a.klabbuildenv" >/dev/null
# A foreign typed object sharing the generic content-addressed warehouse must
# coexist without being mistaken for a buildenv.
mkdir -p "$T/home/artifacts/buildenvs/sha256/foreign-object"
printf 'toolchain\n' >"$T/home/artifacts/buildenvs/sha256/foreign-object/TYPE"
out="$(KLAB_HOME="$T/home" "$ROOT/klab-buildenv.sh" list)"
printf '%s\n' "$out" | grep -Fq "$id" || { echo 'FAIL: imported buildenv missing from inventory' >&2; exit 1; }
printf '%s\n' "$out" | grep -Fq $'test:1:k1\tx86_64\tx86_64' || { echo 'FAIL: inventory metadata missing' >&2; exit 1; }
! printf '%s\n' "$out" | grep -Fq foreign-object || { echo 'FAIL: foreign typed object shown as buildenv' >&2; exit 1; }
printf 'tamper\n' >>"$T/home/artifacts/buildenvs/sha256/$id/installed-packages.tsv"
if KLAB_HOME="$T/home" "$ROOT/klab-buildenv.sh" verify-installed "$id" >/dev/null 2>&1; then
  echo 'FAIL: installed package inventory mutation was not detected' >&2; exit 1
fi
grep -Fq '\${Package}\t\${Version}\t\${Architecture}' "$ROOT/lib/buildenv-capture.sh"
echo 'buildenv-inventory: PASS'
