#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat > "$T/runner" <<'SH2'
#!/bin/sh
sleep .1
exit 0
SH2
chmod +x "$T/runner"
for user in alice bob; do KLAB_ROOT="$T/$user" KLAB_RUNNER="$T/runner" "$ROOT/klab" suite create check >/dev/null; done
KLAB_ROOT="$T/alice" KLAB_RUNNER="$T/runner" "$ROOT/klab" suite run check upstream:v6.6 --arch x86_64 --dry-run >/dev/null & a=$!
KLAB_ROOT="$T/bob" KLAB_RUNNER="$T/runner" "$ROOT/klab" suite run check upstream:v6.6 --arch x86_64 --dry-run >/dev/null & b=$!
wait "$a"; wait "$b"
[[ "$(find "$T/alice/results/suites/check" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 1 ]]
[[ "$(find "$T/bob/results/suites/check" -mindepth 1 -maxdepth 1 -type d | wc -l)" == 1 ]]
! diff -q <(find "$T/alice/results/suites/check" -mindepth 1 -maxdepth 1 -type d -printf '%f\n') <(find "$T/bob/results/suites/check" -mindepth 1 -maxdepth 1 -type d -printf '%f\n') >/dev/null
echo 'PASS: simultaneous users receive isolated roots and collision-resistant queue IDs'
