#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null || true; rm -rf "$T"' EXIT
mkdir -p "$T/root/usr/src/linux-test/scripts" "$T/module"
printf 'all:\n\t@:\n' >"$T/root/usr/src/linux-test/Makefile"
printf '# synthetic\n' >"$T/root/usr/src/linux-test/scripts/Makefile.build"
printf 'pkg 1 x86_64 abc\n' >"$T/packages.txt"
printf 'pkg\t1\tx86_64\n' >"$T/installed.tsv"
# Absolute symlinks in a captured rootfs are rooted inside that rootfs, not
# the host.  Debian/Ubuntu alternatives commonly use this exact shape.
mkdir -p "$T/root/bin" "$T/root/etc/alternatives"
printf '#!/bin/sh\nexit 0\n' >"$T/root/bin/mt-gnu"
chmod +x "$T/root/bin/mt-gnu"
ln -s /etc/alternatives/mt "$T/root/bin/mt"
ln -s /bin/mt-gnu "$T/root/etc/alternatives/mt"
"$ROOT/klab-buildenv.sh" create --root "$T/root" --provider test --release 1 --kernel-release k --target-arch x86_64 --exec-arch x86_64 --provider-image sha256:3333333333333333333333333333333333333333333333333333333333333333 --build-dir usr/src/linux-test --package-manifest "$T/packages.txt" --installed-inventory "$T/installed.tsv" -o "$T/abslinks.klabbuildenv" >/dev/null
"$ROOT/klab-buildenv.sh" verify "$T/abslinks.klabbuildenv" --deep >/dev/null
# Unsafe symlink must be rejected during creation.
ln -s ../../../../etc/passwd "$T/root/usr/src/linux-test/escape"
if "$ROOT/klab-buildenv.sh" create --root "$T/root" --provider test --release 1 --kernel-release k --target-arch x86_64 --exec-arch x86_64 --provider-image sha256:3333333333333333333333333333333333333333333333333333333333333333 --build-dir usr/src/linux-test --package-manifest "$T/packages.txt" --installed-inventory "$T/installed.tsv" -o "$T/bad.klabbuildenv" >/dev/null 2>&1; then
  echo 'FAIL: escaping symlink accepted' >&2; exit 1
fi
rm -f "$T/root/usr/src/linux-test/escape"
# Special files must not enter a buildenv root.
mkfifo "$T/root/fifo"
if "$ROOT/klab-buildenv.sh" create --root "$T/root" --provider test --release 1 --kernel-release k --target-arch x86_64 --exec-arch x86_64 --provider-image sha256:3333333333333333333333333333333333333333333333333333333333333333 --build-dir usr/src/linux-test --package-manifest "$T/packages.txt" --installed-inventory "$T/installed.tsv" -o "$T/bad.klabbuildenv" >/dev/null 2>&1; then
  echo 'FAIL: FIFO accepted' >&2; exit 1
fi
rm -f "$T/root/fifo"
# Valid artifact used for malformed outer/archive tests.
"$ROOT/klab-buildenv.sh" create --root "$T/root" --provider test --release 1 --kernel-release k --target-arch x86_64 --exec-arch x86_64 --provider-image sha256:3333333333333333333333333333333333333333333333333333333333333333 --build-dir usr/src/linux-test --package-manifest "$T/packages.txt" --installed-inventory "$T/installed.tsv" -o "$T/good.klabbuildenv" >/dev/null
mkdir "$T/stage"; tar --zstd -xf "$T/good.klabbuildenv" -C "$T/stage"
printf '%064d  /etc/passwd\n' 0 >>"$T/stage/SHA256SUMS"
tar -C "$T/stage" --zstd -cf "$T/badsum.klabbuildenv" FORMAT_VERSION manifest.json SHA256SUMS payload spec
if "$ROOT/klab-buildenv.sh" verify "$T/badsum.klabbuildenv" >/dev/null 2>&1; then echo 'FAIL: unsafe checksum path accepted' >&2; exit 1; fi
# Traversal entry is rejected before extraction.
python3 - "$T/traversal.tar" <<'PY'
import io,tarfile,sys
with tarfile.open(sys.argv[1],'w') as t:
 d=b'x'; m=tarfile.TarInfo('../escape'); m.size=len(d); t.addfile(m,io.BytesIO(d))
PY
zstd -q -f "$T/traversal.tar" -o "$T/traversal.klabbuildenv"
if "$ROOT/klab-buildenv.sh" verify "$T/traversal.klabbuildenv" >/dev/null 2>&1; then echo 'FAIL: traversal archive accepted' >&2; exit 1; fi
# Execution architecture mismatch must fail before attempting sandbox/toolchain use.
"$ROOT/klab-buildenv.sh" create --root "$T/root" --provider test --release 1 --kernel-release k --target-arch x86_64 --exec-arch aarch64 --provider-image sha256:3333333333333333333333333333333333333333333333333333333333333333 --build-dir usr/src/linux-test --package-manifest "$T/packages.txt" --installed-inventory "$T/installed.tsv" -o "$T/foreign.klabbuildenv" >/dev/null
fid="$("$ROOT/klab-buildenv.sh" verify "$T/foreign.klabbuildenv")"
KLAB_HOME="$T/home" "$ROOT/klab-buildenv.sh" import "$T/foreign.klabbuildenv" >/dev/null
if KLAB_HOME="$T/home" "$ROOT/klab-buildenv.sh" run-module "$fid" --toolchain-root /nonexistent --toolchain-cc bin/gcc --toolchain-tree-sha256 deadbeef --module "$T/module" >/dev/null 2>&1; then
  echo 'FAIL: foreign execution architecture accepted' >&2; exit 1
fi
echo 'buildenv-negative: PASS'
