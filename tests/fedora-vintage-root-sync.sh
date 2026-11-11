#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="$ROOT/providers/fedora.sh"
grep -Fq 'for n in glibc glibc-common; do' "$F" || { echo 'vintage sync does not pin glibc runtime' >&2; exit 1; }
grep -Fq '/klab-distro-toolchain-packages/*.rpm' "$F" || { echo 'vintage sync does not derive exact toolchain runtime set' >&2; exit 1; }
grep -Fq 'rpm -q "$n" >/dev/null 2>&1 || continue' "$F" || { echo 'vintage sync is not limited to installed toolchain packages' >&2; exit 1; }
grep -Fq 'distro-sync $sync_pkgs' "$F" || { echo 'vintage runtime set is not distro-synced to selected Koji repo' >&2; exit 1; }
grep -Fq 'synchronizing modern execution root to recorded Koji buildroot' "$F" || { echo 'modern full-root Koji synchronization missing' >&2; exit 1; }
python3 - "$F" <<'PYTEST'
import pathlib,sys
text=pathlib.Path(sys.argv[1]).read_text()
vintage=text.split('# Do not distro-sync the whole execution image for vintage Fedora.',1)[1]
if 'distro-sync >/dev/null' in vintage:
    raise SystemExit('full-root vintage distro-sync still present')
PYTEST
grep -Fq 'rpm/rpm-python/yum control plane' "$F" || { echo 'rpm control-plane rationale missing' >&2; exit 1; }
echo 'fedora-vintage-root-sync: PASS'
