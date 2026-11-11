#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/xfer" "$TMP/home"
LOG="$TMP/log"
cat > "$TMP/bin/buildenv" <<'S'
#!/usr/bin/env bash
echo "buildenv:$*" >> "$LOGFILE"
S
cat > "$TMP/bin/artifact" <<'S'
#!/usr/bin/env bash
echo "artifact:$*" >> "$LOGFILE"
S
cat > "$TMP/bin/distrotoolchain" <<'S'
#!/usr/bin/env bash
echo "distrotoolchain:$*" >> "$LOGFILE"
S
cat > "$TMP/bin/bundle" <<'S'
#!/usr/bin/env bash
echo "bundle:$*" >> "$LOGFILE"
S
chmod +x "$TMP/bin/"*
touch "$TMP/xfer/a.klabtoolchain" "$TMP/xfer/aa.klabdistrotoolchain" "$TMP/xfer/b.klabbuildenv" "$TMP/xfer/c.klab"
# Extract just the function under test plus minimal globals/helpers from kernel-lab.
python3 - "$ROOT/kernel-lab.sh" "$TMP/harness.sh" <<'PY'
import sys,re
s=open(sys.argv[1]).read()
m=re.search(r'cmd_import_bundle\(\) \{.*?\n\}\n\ncmd_verify_bundle',s,re.S)
assert m
fn=m.group(0).rsplit('\n\ncmd_verify_bundle',1)[0]
open(sys.argv[2],'w').write('''#!/usr/bin/env bash\nset -Eeuo pipefail\nSELF_DIR="$ROOT"\nLAB_HOME="$KLAB_HOME"\nBUILDENV_BIN="$KLAB_BUILDENV_BIN"\nDISTRO_TOOLCHAIN_BIN="$KLAB_DISTRO_TOOLCHAIN_BIN"\nBUNDLE_BIN="$KLAB_BUNDLE_BIN"\nsay(){ :; }\ndie(){ echo "ERR:$*" >&2; exit 1; }\nbundle_tool(){ "$BUNDLE_BIN" "$@"; }\n''' + fn + '\ncmd_import_bundle "$@"\n')
PY
chmod +x "$TMP/harness.sh"
LOGFILE="$LOG" ROOT="$ROOT" KLAB_HOME="$TMP/home" KLAB_BUILDENV_BIN="$TMP/bin/buildenv" KLAB_DISTRO_TOOLCHAIN_BIN="$TMP/bin/distrotoolchain" KLAB_ARTIFACT_BIN="$TMP/bin/artifact" KLAB_BUNDLE_BIN="$TMP/bin/bundle" "$TMP/harness.sh" "$TMP/xfer"
mapfile -t L < "$LOG"
[[ "${L[0]}" == artifact:import*klabtoolchain* ]]
[[ "${L[1]}" == distrotoolchain:import*klabdistrotoolchain* ]]
[[ "${L[2]}" == buildenv:import*klabbuildenv* ]]
[[ "${L[3]}" == bundle:import*\.klab ]]
! grep -F "bundle:import $TMP/xfer" "$LOG"
echo "directory-import-order: PASS"
