#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# --------------------------------------------------------------------------
# 1. .klab importer must preflight exact buildenv binding before destructive
#    replacement of an existing target.
# --------------------------------------------------------------------------
mkdir -p "$T/bundle-fixture" "$T/existing"
printf 'keep-me\n' >"$T/existing/sentinel"
cat >"$T/manifest.json" <<'JSON'
{
  "kind":"distro",
  "target":"ubuntu:17.04:4.10.0-test-generic",
  "provider":"ubuntu",
  "release":"17.04",
  "kernel_release":"4.10.0-test-generic",
  "arch":"x86_64",
  "profile":null,
  "build_image":null,
  "payloads":[{"build_dir_rel":"root/usr/src/linux-test","source_dir_rel":null,"modules_dir_rel":null}],
  "buildenv":{"id":"be-correct","toolchain_tree_sha256":"tc-digest"}
}
JSON
cat >"$T/mock-buildenv" <<'EOF_MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$BE_LOG"
if [[ "${BE_FAIL:-0}" == 1 && "${1:-}" == assert-installed ]]; then exit 9; fi
exit 0
EOF_MOCK
chmod +x "$T/mock-buildenv"
cat >"$T/bundle-fixture/klab-bundle.sh" <<'EOF_FIX'
#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR=/tmp
LAB_HOME="$TEST_HOME"
KERNELS="$TEST_HOME/kernels"
TOOLCHAINS="$TEST_HOME/toolchains"
KERNEL_LAB_BIN="$SELF_DIR/kernel-lab.sh"
say(){ :; }
die(){ echo "DIE: $*" >&2; return 70; }
need_common(){ :; }
canonical_arch(){ echo "$1"; }
quote_env(){ printf '%q' "$1"; }
json_get(){ python3 - "$1" "$2" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
for k in sys.argv[2].split('.'):
    if not k: continue
    x=x[k]
print('' if x is None else x)
PY
}
extract_outer(){ mkdir -p "$2/payload"; cp "$TEST_MANIFEST" "$2/manifest.json"; : >"$2/payload/distro-bundle.tar.zst"; }
verify_stage(){ :; }
bundle_dir_for(){ printf '%s\n' "$TEST_DEST"; }
add_checksum_line(){ :; }
write_manifest(){ :; }
cmd_create_legacy(){
 local stage=/tmp/stage
 write_manifest "$stage/manifest.json" x
 add_checksum_line "$stage" manifest.json
}
fixup_distro_env() {
 local dest="$1" manifest="$2" provider release krel arch build_image build source="" modules=""
 provider="$(json_get "$manifest" provider)"; release="$(json_get "$manifest" release)"; krel="$(json_get "$manifest" kernel_release)"; arch="$(json_get "$manifest" arch)"
 cat > "$dest/bundle.env" <<EOFENV
BUNDLE_PROVIDER=$(quote_env "$provider")
EOFENV
}
cmd_import_legacy() {
  need_common
  local file="$1"; shift
  local force=0 load_image=0
  while (($#)); do case "$1" in --force) force=1;; --load-image) load_image=1;; *) die "unknown";; esac; shift; done
  local tmp; tmp="$(mktemp -d)"; trap "rm -rf '$tmp'" RETURN
  extract_outer "$file" "$tmp"
  verify_stage "$tmp"
  local kind target provider release krel profile arch dest
  kind="$(json_get "$tmp/manifest.json" kind)"; target="$(json_get "$tmp/manifest.json" target)"; provider="$(json_get "$tmp/manifest.json" provider)"; release="$(json_get "$tmp/manifest.json" release)"; krel="$(json_get "$tmp/manifest.json" kernel_release)"; profile="$(json_get "$tmp/manifest.json" profile)"; arch="$(canonical_arch "$(json_get "$tmp/manifest.json" arch)")"
  mkdir -p "$KERNELS" "$TOOLCHAINS"
  if [[ "$kind" == distro ]]; then
    dest="$(bundle_dir_for "$provider" "$release" "$krel" "$arch")"
    if [[ -e "$dest" ]]; then (( force == 1 )) || die exists; rm -rf "$dest"; fi
    mkdir -p "$dest"
    tar --zstd -xf "$tmp/payload/distro-bundle.tar.zst" -C "$dest"
    fixup_distro_env "$dest" "$tmp/manifest.json"
  fi
}
EOF_FIX
python3 "$ROOT/apply-buildenv-transfer.py" "$T/bundle-fixture/klab-bundle.sh" >/dev/null
bash -n "$T/bundle-fixture/klab-bundle.sh"
export TEST_HOME="$T/home" TEST_DEST="$T/existing" TEST_MANIFEST="$T/manifest.json" BE_LOG="$T/be.log" KLAB_BUILDENV_BIN="$T/mock-buildenv"
if BE_FAIL=1 bash -c 'source "$1"; cmd_import_legacy fake.klab --force' _ "$T/bundle-fixture/klab-bundle.sh" >/dev/null 2>&1; then
  echo 'FAIL: target import continued after buildenv preflight failure' >&2; exit 1
fi
[[ -f "$T/existing/sentinel" ]] || { echo 'FAIL: failed dependency preflight destroyed existing target' >&2; exit 1; }
grep -Fq "assert-installed be-correct --provider ubuntu --release 17.04 --kernel-release 4.10.0-test-generic --target-arch x86_64 --exec-arch $(uname -m) --toolchain-tree-sha256 tc-digest" "$T/be.log" || {
  echo 'FAIL: exact target/buildenv binding was not preflighted' >&2; cat "$T/be.log" >&2; exit 1; }

# --------------------------------------------------------------------------
# 2. Directory import must import buildenvs first without leaking target-only
#    options into their importer.
# --------------------------------------------------------------------------
mkdir -p "$T/import-dir"; : >"$T/import-dir/a.klabbuildenv"; : >"$T/import-dir/z.klab"
cat >"$T/kernel-lab.sh" <<'EOF_KL'
#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR=/tmp
LAB_HOME="$TEST_HOME"
BUNDLE_BIN="$SELF_DIR/klab-bundle.sh"
BUILDENV_BIN="$MOCK_BE"
die(){ echo "DIE: $*" >&2; return 70; }
bundle_tool(){ printf '%s\n' "$*" >>"$BUNDLE_LOG"; }
cmd_import_bundle() {
  (($# >= 1)) || die usage
  bundle_tool import "$@"
}
EOF_KL
cat >"$T/mock-be-import" <<'EOF_BEI'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$IMPORT_LOG"
EOF_BEI
chmod +x "$T/mock-be-import"
python3 "$ROOT/apply-buildenv-import.py" "$T/kernel-lab.sh" >/dev/null
bash -n "$T/kernel-lab.sh"
export MOCK_BE="$T/mock-be-import" IMPORT_LOG="$T/import.log" BUNDLE_LOG="$T/bundle.log"
bash -c 'source "$1"; cmd_import_bundle "$2" --force --load-image' _ "$T/kernel-lab.sh" "$T/import-dir"
grep -Fxq "import $T/import-dir/a.klabbuildenv --force" "$T/import.log" || { echo 'FAIL: directory buildenv import flags wrong' >&2; cat "$T/import.log" >&2; exit 1; }
! grep -q -- '--load-image' "$T/import.log" || { echo 'FAIL: target-only --load-image leaked into buildenv importer' >&2; exit 1; }
grep -Fxq "import $T/import-dir --force --load-image" "$T/bundle.log" || { echo 'FAIL: target importer did not retain target options' >&2; exit 1; }

echo 'combined-chain-audit: PASS'
