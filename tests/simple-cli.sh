#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fake="$T/runner"
cat >"$fake" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$KLAB_FAKE_LOG"
SH
chmod +x "$fake"; export KLAB_FAKE_LOG="$T/runner.log" KLAB_STAGE_FREE_GIB=0
bsd="$T/bsd-helper"
cat >"$bsd" <<'SH'
#!/bin/sh
case "$1" in
  supports) case "$2" in freebsd:14.5-RELEASE:riscv64|netbsd:11.0:aarch64) exit 0;; *) exit 1;; esac ;;
  pull|run) printf 'bsd %s\n' "$*" >>"$KLAB_FAKE_LOG" ;;
  list) printf '%s\n' freebsd:14.5-RELEASE:riscv64 netbsd:11.0:aarch64 ;;
esac
SH
chmod +x "$bsd"; export KLAB_BSD_HELPER="$bsd"
indexer="$T/indexer"; printf '#!/bin/sh\nprintf "index %s\n" "$*" >>"$KLAB_FAKE_LOG"\n' >"$indexer"; chmod +x "$indexer"; export KLAB_INDEXER="$indexer"
KLAB_RUNNER="$fake" "$ROOT/klab" setup --root "$T/root" --repo "$T/repo" >"$T/setup.out"
[[ -d "$T/root" && -d "$T/repo" ]]
[[ "$(cat "$T/root/config/offline-repo")" == "$T/repo" ]]
grep -Fq 'init --staging' "$T/runner.log"
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" pull upstream:v6.6 --arch x86_64
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" pull upstream:v2.6.32.71 --arch x86_64
before_index="$(grep -c '^index ' "$T/runner.log")"
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" KLAB_DEFER_REPO_INDEX=1 "$ROOT/klab" pull upstream:v6.7 --arch x86_64 | grep -Fq 'index deferred'
[[ "$(grep -c '^index ' "$T/runner.log")" == "$before_index" ]]
touch "$T/repo/dummy.klab"
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" load "$T/repo/dummy.klab"
grep -Fq 'prepare upstream:v6.6 --artifact-dir ' "$T/runner.log"
grep -Fq -- '--userspace buildroot:minimal --with-sdk --arch x86_64' "$T/runner.log"
grep -Fq 'prepare upstream:v2.6.32.71 --artifact-dir ' "$T/runner.log"
grep -Fq -- '--userspace buildroot:minimal --with-sdk --arch x86_64' "$T/runner.log"
! grep -F 'prepare upstream:v2.6.32.71 ' "$T/runner.log" | grep -q -- '--with-sdk'
grep -Fq 'import ' "$T/runner.log"
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" suite create basic >/dev/null
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" suite show basic | grep -q 'klab-suite-v2'
grep -Fq '"scenario": "scenario.json"' "$T/root/suites/basic/suite.json"
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" suite run basic upstream:v6.6 --arch x86_64 --dry-run --output "$T/suite-run" >/dev/null
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" build upstream:v6.6 --module "$T/root/suites/basic/hello-module" --arch x86_64
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" run upstream:v6.6 --arch x86_64
grep -Fq 'scenario-run ' "$T/runner.log"
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" advanced targets
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" build v6.6 normal
grep -Fq 'targets' "$T/runner.log"
grep -Fq 'build v6.6 normal' "$T/runner.log"
grep -Fq 'build-module upstream:v6.6 --module' "$T/runner.log"
grep -Fq 'smoke upstream:v6.6 --arch x86_64' "$T/runner.log"
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" pull freebsd:14.5-RELEASE:riscv64
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" run freebsd:14.5-RELEASE:riscv64
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" bsd list | grep -q 'netbsd:11.0:aarch64'
grep -Fq "bsd pull freebsd:14.5-RELEASE:riscv64 $T/repo" "$T/runner.log"
grep -Fq "bsd run freebsd:14.5-RELEASE:riscv64 $T/repo $T/root" "$T/runner.log"
! grep -Fq 'prepare freebsd:14.5-RELEASE:riscv64' "$T/runner.log"
[[ "$(KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" repo path)" == "$T/repo" ]]
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" legacy list | grep -q 'linux-2.0.40-i386'
KLAB_ROOT="$T/root" KLAB_RUNNER="$fake" "$ROOT/klab" legacy plan linux-2.6.32-x86_64 | grep -q 'NETWORK_PASS'
echo 'simple-cli: PASS'
