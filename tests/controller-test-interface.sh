#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T" /tmp/klab-test-processes' EXIT
cat >"$T/runner" <<'RUN'
#!/usr/bin/env bash
set -e
cmd="$1"; shift
case "$cmd" in
  build-module) sleep "${KLAB_FAKE_BUILD_DELAY:-0}"; out=''; while (($#)); do [[ "$1" == -o ]] && { out="$2"; shift 2; } || shift; done; mkdir -p "$out"; echo ko >"$out/fake.ko";;
  build-user) out=''; while (($#)); do [[ "$1" == -o ]] && { out="$2"; shift 2; } || shift; done; mkdir -p "$(dirname "$out")"; printf '#!/bin/sh\necho built-ok\n' >"$out"; chmod +x "$out";;
  boot) while (($#)); do if [[ "$1" == --preload ]]; then mkdir -p "$(dirname "$3")"; cp "$2" "$3"; shift 3; else shift; fi; done;;
  stop) :;;
  push) cp "$2" "$3"; chmod +x "$3" 2>/dev/null || true;;
  exec) shift; [[ "$*" == insmod* || "$*" == rmmod* ]] || bash -c "$*";;
  load-module|unload-module) :;;
  *) echo "unexpected runner command: $cmd" >&2; exit 2;;
esac
RUN
chmod +x "$T/runner"
mkdir -p "$T/suite/module"; printf 'obj-m += x.o\n' >"$T/suite/module/Makefile"; echo 'int main(void){return 0;}' >"$T/suite/tool.c"; echo fixture >"$T/suite/input.txt"
cat >"$T/suite/klab.toml" <<'TOML'
[test]
script = "test.sh"
timeout = 10
userspace = "buildroot:minimal"
[module.demo]
source = "module"
[build.tool]
source = "tool.c"
target = "/tmp/klab-built-tool"
[file.input]
source = "input.txt"
target = "/tmp/klab-input"
TOML
cat >"$T/suite/test.sh" <<'TEST'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$KLAB_TARGET" == distro:1 || "$KLAB_TARGET" == freebsd:* ]]
[[ "$KLAB_ARCH" == x86_64 ]]
out="$(klab exec target -- cat "$KLAB_FILE_INPUT")"
klab expect contains "$out" fixture
raw="$(klab exec target 'word=guest; printf "%s" "$word"')"
[[ "$raw" == guest ]]
klab copy target input.txt /tmp/copied-input
copied="$(klab exec target 'cat /tmp/copied-input')"
klab expect contains "$copied" fixture
klab exec target --expect-exit 7 -- sh -c 'exit 7'
klab exec target --expect-failure -- false
built="$(klab exec target -- "$KLAB_BUILD_TOOL")"
klab expect contains "$built" built-ok
klab module load target demo
klab process start target writer 'word=ready; echo "$word"; sleep .2; echo done'
klab process ready target writer stdout ready --timeout 3
klab process wait target writer --timeout 3
output="$(klab process output target writer stdout)"
klab expect matches "$output" 'ready(.|[[:space:]])*done'
TEST
chmod +x "$T/suite/test.sh"
KLAB_ROOT="$T/root" KLAB_RUNNER="$T/runner" "$ROOT/klab" test "$T/suite" on distro:1@x86_64 --output "$T/results" >/dev/null
grep -q $'distro:1@x86_64\tPASS\t0' "$T/results/status.tsv"
[[ "$(cat "$T/results/distro_1__x86_64/RESULT")" == PASS ]]
# FreeBSD boots without Linux-only --preload and receives declarations by push.
KLAB_ROOT="$T/freebsd-root" KLAB_RUNNER="$T/runner" "$ROOT/klab" test "$T/suite" on freebsd:15.1-RELEASE:x86_64@x86_64 --output "$T/freebsd-results" >/dev/null
grep -q $'freebsd:15.1-RELEASE:x86_64@x86_64\tPASS\t0' "$T/freebsd-results/status.tsv"
# An unexpected success must fail the target.
sed -i 's/--expect-failure -- false/--expect-failure -- true/' "$T/suite/test.sh"
set +e; KLAB_ROOT="$T/root2" KLAB_RUNNER="$T/runner" "$ROOT/klab" test "$T/suite" on distro:1@x86_64 --output "$T/fail-results" >/dev/null 2>&1; rc=$?; set -e
[[ $rc -ne 0 ]]; grep -q $'distro:1@x86_64\tFAIL\t' "$T/fail-results/status.tsv"
# Artifact preparation uses the suite timeout and records a row instead of wedging a queue.
sed -i 's/timeout = 10/timeout = 1/' "$T/suite/klab.toml"
set +e; KLAB_FAKE_BUILD_DELAY=2 KLAB_ROOT="$T/root3" KLAB_RUNNER="$T/runner" "$ROOT/klab" test "$T/suite" on distro:1@x86_64 --output "$T/timeout-results" >/dev/null 2>&1; rc=$?; set -e
[[ $rc -ne 0 ]]; grep -q $'distro:1@x86_64\tFAIL\t124' "$T/timeout-results/status.tsv"
echo 'controller test interface: PASS'
