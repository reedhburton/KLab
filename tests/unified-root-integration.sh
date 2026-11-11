#!/usr/bin/env bash
set -Eeuo pipefail
BASE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
# A child must recompute every derived path even with the parent's environment.
export KLAB_ROOT="$t/parent" KLAB_HOME="$t/parent"
source "$BASE/lib/klab-root.sh"
klab_root_ensure_layout
KLAB_ROOT="$t/child" KLAB_HOME="$t/child" "$BASE/klab" init --offline >/dev/null
[[ "$(cat "$t/child/state/MODE")" == offline ]]
[[ ! -e "$t/parent/state/MODE" ]]
for p in builds logs kernels toolchains exports MODE; do
  [[ ! -e "$t/child/$p" && ! -L "$t/child/$p" ]]
done
# Direct Python entry points and shell wrappers agree about roots and stores.
KLAB_ROOT="$t/child" KLAB_HOME="$t/child" python3 - "$BASE/lib" "$t/child" <<'PY'
import pathlib, sys
sys.path.insert(0,sys.argv[1])
from klab_paths import root_home
import klab_buildenv as be, klab_distro_toolchain as dt
root=pathlib.Path(sys.argv[2])
assert root_home()==str(root)
assert be.object_dir(root,'id')==root/'artifacts/buildenvs/sha256/id'
assert dt.object_dir(root,'id')==root/'artifacts/distro-toolchains/sha256/id'
PY
if KLAB_ROOT="$t/child" KLAB_HOME="$t/wrong" "$BASE/klab-buildenv.sh" list >/dev/null 2>&1; then
  echo 'conflicting roots accepted' >&2; exit 1
fi
# Shared artifacts also import into the unified tree without top-level aliases.
mkdir -p "$t/payload"; echo source > "$t/payload/example.c"
KLAB_ROOT="$t/child" KLAB_HOME="$t/child" "$BASE/klab-artifact.sh" create source --from "$t/payload" -o "$t/source.klabsource" >/dev/null
obj="$(KLAB_ROOT="$t/child" KLAB_HOME="$t/child" "$BASE/klab-artifact.sh" import "$t/source.klabsource")"
[[ "$obj" == "$t/child/artifacts/objects/source/"* ]]
[[ -f "$obj/content/example.c" && ! -e "$t/child/objects" && ! -e "$t/child/shared-sources" ]]
# Exercise child-root assignments from the actual capture source with a stub.
python3 - "$BASE/lib/buildenv-capture.sh" "$t" <<'PY'
import os, pathlib, re, subprocess, sys
source=pathlib.Path(sys.argv[1]).read_text(); root=pathlib.Path(sys.argv[2])
stub=root/'assert-root'
stub.write_text('#!/bin/sh\n[ "$KLAB_ROOT" = "$EXPECTED_CHILD" ] && [ "$KLAB_HOME" = "$EXPECTED_CHILD" ]\n')
stub.chmod(0o755)
assignments=re.findall(r'KLAB_ROOT="\$post_home" KLAB_HOME="\$post_home"',source)
assert len(assignments)==5, assignments
for assignment in assignments:
    env=dict(os.environ, EXPECTED_CHILD=str(root/'post'))
    subprocess.run(['/bin/bash','-c', 'post_home="$1"; '+assignment+' "$2"', '_',str(root/'post'),str(stub)],env=env,check=True)
PY
echo 'PASS unified-root integration: child isolation, canonical stores, shared import, capture propagation'
