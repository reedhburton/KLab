#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat >"$T/runner" <<'RUNNER'
#!/usr/bin/env bash
set -eu
[[ "$1" == exec ]]
printf '%s\n' "$3" >>"$CALLS"
exit 0
RUNNER
chmod +x "$T/runner"
CALLS="$T/calls" KLAB_BIN="$T/runner" KLAB_ROOT="$T/root" "$ROOT/klab-buildroot-conformance.sh" session "$T/report" >"$T/out"
grep -Fxq PASS "$T/report/RESULT"
grep -Fq 'test -r /proc/modules' "$T/calls"
grep -Fq 'if test -d /lib/modules; then test -d /lib/modules/$(uname -r); fi' "$T/calls"
! grep -Fq 'test -d /lib/modules/$(uname -r); cat' "$ROOT/klab-buildroot-conformance.sh"
echo 'Buildroot conformance accepts module-capable guests without an empty modules tree: PASS'
