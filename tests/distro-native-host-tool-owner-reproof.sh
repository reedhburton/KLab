#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/klab-buildenv.sh"
grep -q 'actual_owner=$(dpkg-query -S "$resolved"' "$f"
grep -q 'actual_owner=$(rpm -qf --qf' "$f"
grep -q 'host-tool package owner mismatch:' "$f"
grep -q 'sealed root has no supported package ownership database' "$f"
grep -Fq 'IFS="$(printf "\t")" read -r logical resolved owner' "$f"
line="awk$(printf '\011')/usr/bin/mawk$(printf '\011')mawk"
IFS="$(printf '\011')" read -r logical resolved owner <<EOF
$line
EOF
[[ "$logical" == awk && "$resolved" == /usr/bin/mawk && "$owner" == mawk ]]
echo 'distro-native host-tool owner reproof: PASS'
