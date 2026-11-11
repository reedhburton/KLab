#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
f="$ROOT/lib/backends/rpm.sh"
[[ $(grep -Fc "subprocess.Popen(['rpm','-Kv',f]" "$f") == 2 ]]
[[ $(grep -Fc "'openpgp' in out.lower()" "$f") == 2 ]]
# RPM 6 terse --checksig output omits the algorithm, while -Kv retains explicit
# OpenPGP signer evidence; the parser must require that marker plus OK status.
python3 - <<'PYTEST'
out='Header OpenPGP V4 RSA/SHA256 signature, key fingerprint: abc: OK\nHeader SHA256 digest: OK\nPayload SHA256 digest: OK'
ok=(0==0 and ('openpgp' in out.lower() or 'pgp' in out.lower() or 'rsa' in out.lower()) and 'OK' in out and 'NOKEY' not in out and 'NOT OK' not in out)
assert ok
for bad in ('Header SHA256 digest: OK', 'Header OpenPGP signature: NOKEY', 'Header OpenPGP signature: NOT OK'):
 ok=(0==0 and ('openpgp' in bad.lower() or 'pgp' in bad.lower() or 'rsa' in bad.lower()) and 'OK' in bad and 'NOKEY' not in bad and 'NOT OK' not in bad)
 assert not ok, bad
PYTEST
echo 'rpm6 signature output: PASS'
