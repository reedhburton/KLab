#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
p="$ROOT/providers/centos.sh"
grep -Fq '6341AB2753D78A78A7C27BB124C6A8A7F4A80EB5' "$p" || { echo 'FAIL: CentOS 7 official signing-key fingerprint is not pinned' >&2; exit 1; }
grep -Fq 'gpg --quiet --with-fingerprint "$key"' "$p" || { echo 'FAIL: CentOS 7 key file is not fingerprint-checked' >&2; exit 1; }
[[ $(grep -c 'baseurl=https://vault.centos.org/7.9.2009/' "$p") -eq 2 ]] || { echo 'FAIL: CentOS 7 Vault URLs are not HTTPS' >&2; exit 1; }
[[ $(grep -c 'https://archive.kernel.org/centos-vault/7.9.2009/' "$p") -eq 2 ]] || { echo 'FAIL: pinned HTTPS CentOS Vault fallback is missing' >&2; exit 1; }
! grep -q 'baseurl=http://vault.centos.org/7.9.2009/' "$p" || { echo 'FAIL: plaintext CentOS 7 Vault URL remains' >&2; exit 1; }
python3 - "$ROOT/lib/backends/rpm.sh" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text()
yum=s[s.index('klab_backend_yum_capture_toolchain()'):]
assert 'subprocess.run' not in yum, 'CentOS 7 provenance still requires Python 3 subprocess.run'
assert "subprocess.Popen(['rpm','-Kv'" in yum
PY
echo 'PASS: CentOS 7 Vault transport and signing-key identity are pinned'
