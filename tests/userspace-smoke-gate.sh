#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat >"$T/runner" <<'RUNNER'
#!/usr/bin/env bash
set -eu
printf '%s|offline=%s\n' "$*" "${KLAB_OFFLINE:-}" >>"$FAKE_CALLS"
case "$1" in
 boot) exit 0 ;;
 exec) printf 'KLAB_USERSPACE_SMOKE_PASS kernel=6.6-test arch=x86_64\n'; exit 0 ;;
 stop) exit 0 ;;
 *) exit 2 ;;
esac
RUNNER
chmod +x "$T/runner"
export FAKE_CALLS="$T/calls" KLAB_RUNNER="$T/runner" KLAB_ROOT="$T/root" KLAB_OFFLINE=1
"$ROOT/klab-userspace-smoke.sh" distro:1:6.6-test x86_64 auto "$T/report" >"$T/out"
grep -Fq 'boot distro:1:6.6-test --arch x86_64 --userspace auto --name valquick-' "$T/calls"
grep -Fq 'exec valquick-' "$T/calls"
grep -Fq 'stop valquick-' "$T/calls"
[[ "$(grep -c 'offline=1' "$T/calls")" -eq 3 ]]
grep -Fq KLAB_USERSPACE_SMOKE_PASS "$T/report/exec.log"
grep -Fq 'KLab userspace smoke: PASS' "$T/out"
echo 'direct userspace smoke gate: PASS'
