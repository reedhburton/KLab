#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/providers/fedora.sh"

grep -Fq 'install_kbuild_prereqs(){' "$F" || { echo 'Fedora Kbuild prerequisite installer missing' >&2; exit 1; }
grep -Fq '"$pm" -y -q $repo_args install elfutils-libelf-devel' "$F" || {
  echo 'Fedora buildenv does not install the libelf headers required by objtool' >&2; exit 1;
}
[[ "$(grep -c 'install_kbuild_prereqs dnf' "$F")" == 1 ]] || { echo 'DNF prerequisite install missing or duplicated' >&2; exit 1; }
[[ "$(grep -c 'install_kbuild_prereqs yum' "$F")" == 1 ]] || { echo 'Yum prerequisite install missing or duplicated' >&2; exit 1; }

python3 - "$F" <<'PY2'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
for pm in ('dnf', 'yum'):
    select = s.index(f'select_repo {pm}')
    prereq = s.index(f'install_kbuild_prereqs {pm}', select)
    kernel = s.index(f'{pm} -y -q $repo_args ', prereq)
    if not select < prereq < kernel:
        raise SystemExit(f'{pm}: prerequisites are not installed from the selected historical repository before kernel RPMs')
PY2

echo 'PASS: Fedora buildenv seals objtool/libelf prerequisites from its selected historical repository'
