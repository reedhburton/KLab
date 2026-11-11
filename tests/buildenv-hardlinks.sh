#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/lib/klab_buildenv.py"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/good/bin"
printf 'payload\n' > "$TMP/good/bin/bzip2"
ln "$TMP/good/bin/bzip2" "$TMP/good/bin/bzcat"
tar -C "$TMP/good" -cf - . | zstd -q -c > "$TMP/good.tar.zst"

python3 - "$PY" "$TMP/good.tar.zst" <<'PY'
import importlib.util, sys
sys.path.insert(0, __import__('os').path.dirname(sys.argv[1]))
spec=importlib.util.spec_from_file_location('kb',sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.safe_tar_members(sys.argv[2], payload=True)
PY

# Construct a hardlink whose target traverses outside the archive namespace.
python3 - "$TMP/bad.tar" <<'PY'
import io, tarfile, sys
with tarfile.open(sys.argv[1], 'w') as tf:
    data=b'ok\n'; r=tarfile.TarInfo('bin/real'); r.size=len(data); tf.addfile(r,io.BytesIO(data))
    h=tarfile.TarInfo('bin/bad'); h.type=tarfile.LNKTYPE; h.linkname='../../etc/passwd'; tf.addfile(h)
PY
zstd -q -c "$TMP/bad.tar" > "$TMP/bad.tar.zst"
if python3 - "$PY" "$TMP/bad.tar.zst" <<'PY' 2>/dev/null
import importlib.util, sys
sys.path.insert(0, __import__('os').path.dirname(sys.argv[1]))
spec=importlib.util.spec_from_file_location('kb',sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.safe_tar_members(sys.argv[2], payload=True)
PY
then
  echo 'FAIL: escaping hardlink was accepted' >&2; exit 1
fi

echo 'PASS: buildenv hardlinks preserve normal rootfs hardlinks and reject escaping targets'
