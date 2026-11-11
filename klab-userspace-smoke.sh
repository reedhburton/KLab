#!/usr/bin/env bash
set -euo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
KLAB_BIN="${KLAB_RUNNER:-$SELF/kernel-lab.sh}"
KLAB_ROOT="${KLAB_ROOT:-$HOME/klab-data}"
export KLAB_ROOT

usage() {
  echo 'usage: klab-userspace-smoke.sh TARGET ARCH USERSPACE REPORT_DIR' >&2
  exit 2
}
[[ $# -eq 4 ]] || usage
target="$1"; arch="$2"; userspace="$3"; report="$4"
mkdir -p "$report"
digest="$(printf '%s' "$target-$arch-$$-$(date +%s%N)" | sha256sum | cut -c1-12)"
session="valquick-$digest"
cleanup() {
  timeout 120 "$KLAB_BIN" stop "$session" >>"$report/stop.log" 2>&1 || true
  root="$KLAB_ROOT/work/initramfs/session_${session}.session.root"
  [[ ! -d "$root" ]] || chmod -R u+w "$root" 2>/dev/null || true
  rm -rf "$root" "$KLAB_ROOT/work/initramfs/session_${session}.session.cpio.gz" "$KLAB_ROOT/work/sessions/$session" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

"$KLAB_BIN" boot "$target" --arch "$arch" --userspace "$userspace" --name "$session" >"$report/boot.log" 2>&1
provider="${target%%:*}"
if [[ "$target" == *:*:* && "$provider" != upstream && "$provider" != custom ]]; then
  expected="${target##*:}"
  command="test \"\$(uname -r)\" = '$expected'; d=/tmp/klab-userspace-smoke.\$\$; mkdir \"\$d\"; printf KLAB_USERSPACE_DATA >\"\$d/input\"; (cat \"\$d/input\" >\"\$d/output\") & p=\$!; wait \"\$p\"; grep -q KLAB_USERSPACE_DATA \"\$d/output\"; rm -rf \"\$d\"; printf 'KLAB_USERSPACE_SMOKE_PASS kernel=%s arch=%s\\n' \"\$(uname -r)\" \"\$(uname -m)\""
else
  command='k=$(uname -r); test -n "$k"; d=/tmp/klab-userspace-smoke.$$; mkdir "$d"; printf KLAB_USERSPACE_DATA >"$d/input"; (cat "$d/input" >"$d/output") & p=$!; wait "$p"; grep -q KLAB_USERSPACE_DATA "$d/output"; rm -rf "$d"; printf "KLAB_USERSPACE_SMOKE_PASS kernel=%s arch=%s\n" "$k" "$(uname -m)"'
fi
"$KLAB_BIN" exec "$session" "$command" >"$report/exec.log" 2>&1
grep -q KLAB_USERSPACE_SMOKE_PASS "$report/exec.log"
printf 'KLab userspace smoke: PASS\ntarget=%s\narch=%s\nuserspace=%s\nsession=%s\n' "$target" "$arch" "$userspace" "$session"
