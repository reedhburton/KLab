#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TARGET="${1:-}"
[[ -n "$TARGET" && -d "$TARGET" ]] || { echo "Usage: $0 /path/to/klab-source-tree" >&2; exit 2; }
TARGET="$(cd "$TARGET" && pwd)"
[[ -f "$TARGET/kernel-lab.sh" ]] || { echo "Missing $TARGET/kernel-lab.sh" >&2; exit 2; }

stamp="$(date +%Y%m%d-%H%M%S)"
backup="$TARGET/.klab-root-layout-backup-$stamp"
mkdir -p "$backup" "$TARGET/lib"
[[ "$SELF_DIR" == "$TARGET" ]] || cp "$SELF_DIR/lib/klab-root.sh" "$TARGET/lib/klab-root.sh"
[[ "$SELF_DIR" == "$TARGET" ]] || cp "$SELF_DIR/klab-root" "$TARGET/klab-root"
[[ "$SELF_DIR" == "$TARGET" ]] || cp "$SELF_DIR/klab" "$TARGET/klab"
chmod +x "$TARGET/klab-root" "$TARGET/klab" "$TARGET/lib/klab-root.sh"

patch_one() {
  local f="$1" base
  [[ -f "$f" ]] || return 0
  base="$(basename "$f")"
  if ! grep -q 'KLAB_UNIFIED_ROOT_R22' "$f"; then
  cp -a "$f" "$backup/$base"
  python3 - "$f" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
needle='set -Eeuo pipefail\n'
if needle not in s:
    raise SystemExit(f"no strict-mode anchor in {p}")
insert='''set -Eeuo pipefail

# KLAB_UNIFIED_ROOT_R22
_KLAB_SELF_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [[ -f "$_KLAB_SELF_DIR/lib/klab-root.sh" ]]; then
  # shellcheck source=lib/klab-root.sh
  source "$_KLAB_SELF_DIR/lib/klab-root.sh"
  klab_root_ensure_layout
fi
unset _KLAB_SELF_DIR
'''
s=s.replace(needle,insert,1)
p.write_text(s)
PY
  fi

  # R23 removes first-party dependence on legacy top-level compatibility paths.
  # Keep this as a text-level migration so it can be applied safely on top of
  # later R14-R21 trees without reconstructing those releases.
  if ! grep -q 'KLAB_NATIVE_PATHS_R23' "$f"; then
    cp -a "$f" "$backup/$base.r23"
    python3 - "$f" <<'PY_R23'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
repl={
    'LAB_HOME="${KLAB_HOME:-$PWD/kernel-lab}"':'LAB_HOME="$KLAB_ROOT"',
    'SRC="$LAB_HOME/linux"':'SRC="$KLAB_CACHE/linux"',
    'SOURCES="$LAB_HOME/sources"':'SOURCES="$KLAB_CACHE/sources"',
    'BUILDS="$LAB_HOME/builds"':'BUILDS="$KLAB_WORK/builds"',
    'INITRAMFS="$LAB_HOME/initramfs"':'INITRAMFS="$KLAB_WORK/initramfs"',
    'LOGS="$LAB_HOME/logs"':'LOGS="$KLAB_RESULTS/logs"',
    'EXAMPLES="$LAB_HOME/examples"':'EXAMPLES="$KLAB_STATE/examples"',
    'KERNELS="$LAB_HOME/kernels"':'KERNELS="$KLAB_TARGETS/kernels"',
    'TOOLCHAINS="$LAB_HOME/toolchains"':'TOOLCHAINS="$KLAB_TOOLCHAIN_STORE"',
    'JOBS_ROOT="$LAB_HOME/jobs"':'JOBS_ROOT="$KLAB_WORK/jobs"',
    'SESSIONS="$LAB_HOME/sessions"':'SESSIONS="$KLAB_WORK/sessions"',
    'ARTIFACTS="$LAB_HOME/artifacts"':'ARTIFACTS="$KLAB_ARTIFACTS"',
    'CRASHES="$LAB_HOME/crashes"':'CRASHES="$KLAB_RESULTS/crashes"',
    'EXPORTS="$LAB_HOME/exports"':'EXPORTS="$KLAB_TRANSFER/exports"',
    'GUESTS="$LAB_HOME/guests"':'GUESTS="$KLAB_USERSPACE_STORE"',
    'BUILDROOT_HOME="$LAB_HOME/buildroot"':'BUILDROOT_HOME="$KLAB_WORK/buildroot"',
    'MODE_FILE="$LAB_HOME/MODE"':'MODE_FILE="$KLAB_STATE/MODE"',
    'BUILDENVS="$LAB_HOME/buildenvs"':'BUILDENVS="$KLAB_BUILDENV_STORE"',
    'BUILDENV_STORE="$LAB_HOME/buildenvs"':'BUILDENV_STORE="$KLAB_BUILDENV_STORE"',
    'DISTRO_TOOLCHAINS="$LAB_HOME/distro-toolchains"':'DISTRO_TOOLCHAINS="$KLAB_DISTRO_TOOLCHAIN_STORE"',
    'DISTRO_TOOLCHAIN_STORE="$LAB_HOME/distro-toolchains"':'DISTRO_TOOLCHAIN_STORE="$KLAB_DISTRO_TOOLCHAIN_STORE"',
    'USERSPACES="$LAB_HOME/userspaces"':'USERSPACES="$KLAB_USERSPACE_STORE"',
    'USERSPACE_STORE="$LAB_HOME/userspaces"':'USERSPACE_STORE="$KLAB_USERSPACE_STORE"',
}
for a,b in repl.items(): s=s.replace(a,b)
# Also rewrite direct uses, not just top-level variable declarations. This
# covers newer helpers that address stores inline.
fragments={
    'linux':'$KLAB_CACHE/linux',
    'sources':'$KLAB_CACHE/sources',
    'builds':'$KLAB_WORK/builds',
    'initramfs':'$KLAB_WORK/initramfs',
    'logs':'$KLAB_RESULTS/logs',
    'examples':'$KLAB_STATE/examples',
    'kernels':'$KLAB_TARGETS/kernels',
    'toolchains':'$KLAB_TOOLCHAIN_STORE',
    'jobs':'$KLAB_WORK/jobs',
    'sessions':'$KLAB_WORK/sessions',
    'artifacts':'$KLAB_ARTIFACTS',
    'crashes':'$KLAB_RESULTS/crashes',
    'exports':'$KLAB_TRANSFER/exports',
    'guests':'$KLAB_USERSPACE_STORE',
    'buildroot':'$KLAB_WORK/buildroot',
    'buildenvs':'$KLAB_BUILDENV_STORE',
    'distro-toolchains':'$KLAB_DISTRO_TOOLCHAIN_STORE',
    'userspaces':'$KLAB_USERSPACE_STORE',
}
for name,dst in fragments.items():
    for prefix in ('$LAB_HOME/', '${LAB_HOME}/', '$KLAB_HOME/', '${KLAB_HOME}/'):
        s=s.replace(prefix+name, dst)
anchor='# KLAB_UNIFIED_ROOT_R22\n'
if anchor in s:
    s=s.replace(anchor, anchor+'# KLAB_NATIVE_PATHS_R23\n', 1)
else:
    # This should be rare, but keep a positive marker for idempotence.
    strict='set -Eeuo pipefail\n'
    if strict not in s: raise SystemExit(f'no strict-mode anchor in {p}')
    s=s.replace(strict, strict+'# KLAB_NATIVE_PATHS_R23\n',1)
p.write_text(s)
PY_R23
  fi

  # R24 closes residual root-path forms that R23's direct fragment rewrite could
  # not safely recognize, and updates user-facing environment guidance.
  if ! grep -q 'KLAB_RESIDUAL_PATH_AUDIT_R24' "$f"; then
    cp -a "$f" "$backup/$base.r24"
    python3 - "$f" <<'PY_R24'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
name=p.name
# Public configuration is KLAB_ROOT. Keep KLAB_HOME only as the compatibility
# alias implemented by lib/klab-root.sh, not as guidance or a path owner.
s=s.replace('  KLAB_HOME, KLAB_JOBS,', '  KLAB_ROOT, KLAB_JOBS,')
s=s.replace('  KLAB_HOME, KLAB_ARCH, KLAB_CONTAINER_RUNTIME, KLAB_KERNEL_LAB_BIN',
            '  KLAB_ROOT, KLAB_ARCH, KLAB_CONTAINER_RUNTIME, KLAB_KERNEL_LAB_BIN')
s=s.replace('KLAB_HOME="$LAB_HOME" KLAB_ARCH="$ARCH"',
            'KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" KLAB_ARCH="$ARCH"')
s=s.replace('export KLAB_HOME="$LAB_HOME" KLAB_OFFLINE=',
            'export KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME" KLAB_OFFLINE=')
if name == 'klab-buildroot-cache.sh':
    s=s.replace('--dest /srv/kernel-lab/buildroot', '--dest /srv/kernel-lab/work/buildroot')
    s=s.replace('Then point Kernel Lab at /srv/kernel-lab (KLAB_HOME=/srv/kernel-lab). The\ninstalled cache lands in /srv/kernel-lab/buildroot/dl and the Buildroot source\ntarball lands in /srv/kernel-lab/buildroot/downloads.',
                'Then point Kernel Lab at /srv/kernel-lab (KLAB_ROOT=/srv/kernel-lab). The\ninstalled cache lands in /srv/kernel-lab/work/buildroot/dl and the Buildroot source\ntarball lands in /srv/kernel-lab/work/buildroot/downloads.')
    s=s.replace('  KLAB_HOME=/srv/kernel-lab ./kernel-lab.sh buildroot-cache check --all',
                '  KLAB_ROOT=/srv/kernel-lab ./kernel-lab.sh buildroot-cache check --all')
    s=s.replace('<KLAB_HOME>/buildroot with klab-buildroot-cache.sh install.',
                '<KLAB_ROOT>/work/buildroot with klab-buildroot-cache.sh install.')
    old = "printf 'Next: KLAB_HOME=%q ./kernel-lab.sh buildroot-cache check --all\\n' \"$(dirname \"$dest\")\" >&2"
    new = "printf 'Next: KLAB_ROOT=%q ./kernel-lab.sh buildroot-cache check --all\\n' \"$KLAB_ROOT\" >&2"
    s=s.replace(old, new)
    s=s.replace('local archive="$1" dest="${KLAB_BUILDROOT_DEST:-${KLAB_HOME:-$PWD/kernel-lab}/buildroot}"; shift',
                'local archive="$1" dest="${KLAB_BUILDROOT_DEST:-$KLAB_WORK/buildroot}"; shift')
# Mark the file without requiring a second root helper injection.
mark='# KLAB_NATIVE_PATHS_R23\n'
if mark in s:
    s=s.replace(mark, mark+'# KLAB_RESIDUAL_PATH_AUDIT_R24\n', 1)
elif '# KLAB_UNIFIED_ROOT_R22\n' in s:
    s=s.replace('# KLAB_UNIFIED_ROOT_R22\n', '# KLAB_UNIFIED_ROOT_R22\n# KLAB_RESIDUAL_PATH_AUDIT_R24\n', 1)
p.write_text(s)
PY_R24
  fi
}

for f in \
  "$TARGET/kernel-lab.sh" \
  "$TARGET/klab-bundle.sh" \
  "$TARGET/klab-buildroot-cache.sh" \
  "$TARGET/klab-artifact.sh" \
  "$TARGET/klab-buildenv.sh" \
  "$TARGET/klab-distro-toolchain.sh"; do
  patch_one "$f"
done

# The live-test harness intentionally creates an isolated child root. Do not
# source the parent root helper into the harness itself; just place the child
# beneath the configured main root and let child KLab commands derive paths.
if [[ -f "$TARGET/klab-live-test.sh" ]]; then
  if ! grep -q 'KLAB_UNIFIED_ROOT_R22_LIVE' "$TARGET/klab-live-test.sh"; then
    cp -a "$TARGET/klab-live-test.sh" "$backup/klab-live-test.sh"
    python3 - "$TARGET/klab-live-test.sh" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
s=s.replace('set -Eeuo pipefail\n', 'set -Eeuo pipefail\n# KLAB_UNIFIED_ROOT_R22_LIVE\n', 1)
s=s.replace('LIVE_HOME="$HOME/klab-live-$(date +%Y%m%d-%H%M%S)"',
            'LIVE_HOME="${KLAB_ROOT:-${KLAB_HOME:-$HOME/klab}}/work/live-tests/$(date +%Y%m%d-%H%M%S)"')
s=s.replace('export KLAB_HOME="$LIVE_HOME"', '''export KLAB_ROOT="$LIVE_HOME"
export KLAB_HOME="$KLAB_ROOT"
# Prevent inherited path-derived values from escaping the isolated child root.
unset KLAB_BIN KLAB_CONFIG KLAB_ARTIFACTS KLAB_ARTIFACT_KERNELS \
  KLAB_BUILDENV_STORE KLAB_TOOLCHAIN_STORE KLAB_DISTRO_TOOLCHAIN_STORE \
  KLAB_USERSPACE_STORE KLAB_SOURCE_ARTIFACT_STORE KLAB_TARGETS KLAB_CACHE \
  KLAB_WORK KLAB_TRANSFER KLAB_RESULTS KLAB_STATE KLAB_BUILDROOT_CACHE_HOME''')
p.write_text(s)
PY
  fi
  if ! grep -q 'KLAB_RESIDUAL_PATH_AUDIT_R24_LIVE' "$TARGET/klab-live-test.sh"; then
    cp -a "$TARGET/klab-live-test.sh" "$backup/klab-live-test.sh.r24"
    python3 - "$TARGET/klab-live-test.sh" <<'PY_R24_LIVE'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
s=s.replace('# KLAB_UNIFIED_ROOT_R22_LIVE\n', '# KLAB_UNIFIED_ROOT_R22_LIVE\n# KLAB_RESIDUAL_PATH_AUDIT_R24_LIVE\n', 1)
s=s.replace('Isolated KLAB_HOME', 'Isolated child KLAB_ROOT')
s=s.replace('It creates a fresh KLAB_HOME unless --home is given.', 'It creates a fresh child KLAB_ROOT unless --home is given.')
s=s.replace('retained under KLAB_HOME/live-test-logs.', 'retained under the child KLAB_ROOT/live-test-logs.')
s=s.replace('HOME/KLAB_HOME ownership', 'HOME/KLAB_ROOT ownership')
s=s.replace('KLAB_HOME was isolated at: $KLAB_HOME', 'KLAB_ROOT was isolated at: $KLAB_ROOT')
p.write_text(s)
PY_R24_LIVE
  fi
fi

# R29 covers the actual R28 helpers, beyond the older synthetic fixtures.
python3 - "$TARGET" <<'PY_R29'
from pathlib import Path
import re, sys
root=Path(sys.argv[1])
for name in ('kernel-lab.sh','klab-bundle.sh','klab-buildenv.sh','klab-artifact.sh','lib/buildenv-capture.sh','live-validation-ubuntu1704.sh'):
    p=root/name
    if not p.exists(): continue
    s=p.read_text()
    # Propagate the same root identity, including temporary post-capture roots.
    s=re.sub(r'(?<!KLAB_ROOT="\$LAB_HOME" )KLAB_HOME="\$LAB_HOME"', 'KLAB_ROOT="$LAB_HOME" KLAB_HOME="$LAB_HOME"', s)
    for variable in ('post_home','STAGE','OFFLINE','KLAB_ROOT'):
        alias=f'KLAB_HOME="${variable}"'
        both=f'KLAB_ROOT="${variable}" {alias}'
        s=s.replace(both,alias).replace(alias,both)
    s=s.replace('${KLAB_HOME:-$PWD/kernel-lab}', '$KLAB_ROOT')
    s=s.replace('%s/artifacts/objects/sha256/%s', '%s/artifacts/buildenvs/sha256/%s')
    s=s.replace('$KLAB_ARTIFACTS/objects/sha256/$buildenv_id', '$KLAB_BUILDENV_STORE/sha256/$buildenv_id')
    if name=='klab-artifact.sh':
        s=s.replace('OBJECTS="$LAB_HOME/objects"','OBJECTS="$KLAB_ARTIFACTS/objects"')
        s=s.replace('FIRMWARE="$LAB_HOME/firmware"','FIRMWARE="$KLAB_ARTIFACTS/firmware"')
        s=s.replace('SOURCES_SHARED="$LAB_HOME/shared-sources"','SOURCES_SHARED="$KLAB_SOURCE_ARTIFACT_STORE"')
    p.write_text(s)
for name,old,new in (
    ('klab_buildenv.py','artifacts/objects/sha256','artifacts/buildenvs/sha256'),
    ('klab_distro_toolchain.py','artifacts/toolchains/sha256','artifacts/distro-toolchains/sha256')):
    p=root/'lib'/name
    if not p.exists(): continue
    s=p.read_text().replace(old,new)
    s=s.replace("a.home or os.environ.get('KLAB_HOME','kernel-lab')", 'root_home(a.home)')
    if 'from klab_paths import root_home' not in s:
        s=s.replace('def object_dir(', 'from klab_paths import root_home\n\ndef object_dir(',1)
    p.write_text(s)
PY_R29
if [[ "$SELF_DIR" != "$TARGET" && -f "$SELF_DIR/lib/klab_paths.py" ]]; then
  cp "$SELF_DIR/lib/klab_paths.py" "$TARGET/lib/klab_paths.py"
fi

native_path_audit() {
  local f hit=0
  # Executable-path ownership: reject simple and nested KLAB_HOME/LAB_HOME forms
  # that point at directories now owned by canonical KLAB_* variables.
  local re_simple='\$(LAB_HOME|KLAB_HOME)/(linux|sources|builds|initramfs|logs|examples|kernels|toolchains|jobs|sessions|artifacts|crashes|exports|guests|buildroot|buildenvs|distro-toolchains|userspaces)(/|["'"'"'[:space:]]|$)|\$\{(LAB_HOME|KLAB_HOME)\}/(linux|sources|builds|initramfs|logs|examples|kernels|toolchains|jobs|sessions|artifacts|crashes|exports|guests|buildroot|buildenvs|distro-toolchains|userspaces)(/|["'"'"'[:space:]]|$)'
  local re_nested='\$\{KLAB_HOME:-[^}]*\}/(linux|sources|builds|initramfs|logs|examples|kernels|toolchains|jobs|sessions|artifacts|crashes|exports|guests|buildroot|buildenvs|distro-toolchains|userspaces)'
  for f in "$TARGET/kernel-lab.sh" "$TARGET/klab-bundle.sh" "$TARGET/klab-buildroot-cache.sh" "$TARGET/klab-buildenv.sh" "$TARGET/klab-distro-toolchain.sh" "$TARGET/klab-artifact.sh"; do
    [[ -f "$f" ]] || continue
    if grep -En "$re_simple|$re_nested" "$f" >/dev/null 2>&1; then
      printf 'ERROR: residual legacy-root path references in %s:\n' "$f" >&2
      grep -En "$re_simple|$re_nested" "$f" >&2 || true
      hit=1
    fi
    # User-facing helpers must advertise KLAB_ROOT, not KLAB_HOME. Exempt only
    # compatibility implementation files, which are outside this loop.
    if grep -En '(^|[^A-Za-z0-9_])KLAB_HOME([=/, )]|$)|<KLAB_HOME>' "$f" >/dev/null 2>&1; then
      # Internal propagation as an alias is allowed only when KLAB_ROOT is set on
      # the same line. Everything else is stale guidance or ownership.
      while IFS=: read -r ln txt; do
        [[ -n "$ln" ]] || continue
        if [[ "$txt" == *'KLAB_HOME="$LAB_HOME"'* && "$txt" == *'KLAB_ROOT="$LAB_HOME"'* ]] || [[ "$txt" == *'KLAB_ROOT="$KLAB_ROOT" KLAB_HOME="$KLAB_ROOT"'* ]]; then
          continue
        fi
        printf 'ERROR: stale KLAB_HOME public/path reference in %s:%s:%s\n' "$f" "$ln" "$txt" >&2
        hit=1
      done < <(grep -En '(^|[^A-Za-z0-9_])KLAB_HOME([=/, )]|$)|<KLAB_HOME>' "$f" || true)
    fi
  done
  return "$hit"
}

if native_path_audit; then
  printf 'Residual-path audit: PASS\n'
else
  printf 'Residual-path audit: FAIL (see references above)\n' >&2
  exit 1
fi

printf 'Applied unified-root overlay to %s\n' "$TARGET"
printf 'Backups: %s\n' "$backup"
printf 'Next: KLAB_ROOT=~/klab %s/klab-root init\n' "$TARGET"
