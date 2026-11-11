#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat >"$T/klab-bundle.sh" <<'FIX'
#!/usr/bin/env bash
set -Eeuo pipefail
KERNELS="$TEST_HOME/kernels"; TOOLCHAINS="$TEST_HOME/toolchains"; LAB_HOME="$TEST_HOME"
die(){ echo "DIE: $*" >&2; return 70; }
need_common(){ :; }
json_get(){ case "$2" in kind) echo "${TEST_KIND:-distro}";; target) echo test:1:k;; provider) echo test;; release) echo 1;; kernel_release) echo k;; profile) echo normal;; arch) echo x86_64;; *) echo '';; esac; }
canonical_arch(){ echo "$1"; }
extract_outer(){ mkdir -p "$2/payload"; : >"$2/manifest.json"; : >"$2/payload/distro-bundle.tar.zst"; : >"$2/payload/source.tar.zst"; : >"$2/payload/build.tar.zst"; }
verify_stage(){ :; }
bundle_dir_for(){ echo "$TEST_DEST"; }
fixup_distro_env(){ printf 'new\n' >"$1/new-sentinel"; if [[ "${FAIL_FIXUP:-0}" == 1 ]]; then mkdir -p "$1/readonly"; printf locked >"$1/readonly/file"; chmod -R a-w "$1/readonly"; die 'synthetic fixup failure'; fi; }
cmd_import_legacy() {
  need_common
  local file="$1"; shift
  local force=0 load_image=0
  while (($#)); do case "$1" in --force) force=1;; --load-image) load_image=1;; *) die bad;; esac; shift; done
  local tmp; tmp="$(mktemp -d)"; trap "rm -rf '$tmp'" EXIT
  extract_outer "$file" "$tmp"
  verify_stage "$tmp"
  local kind target provider release krel profile arch dest
  kind="$(json_get "$tmp/manifest.json" kind)"; target=x; provider=test; release=1; krel=k; profile=normal; arch=x86_64
  mkdir -p "$KERNELS" "$TOOLCHAINS" "$LAB_HOME/logs" "$LAB_HOME/jobs" "$LAB_HOME/initramfs"
  if [[ "$kind" == distro ]]; then
    dest="$(bundle_dir_for "$provider" "$release" "$krel" "$arch")"
    if [[ -e "$dest" ]]; then
      (( force == 1 )) || die "destination already exists: $dest (use --force to replace)"
      rm -rf "$dest"
    fi
    mkdir -p "$dest"
    : # synthetic extraction
    fixup_distro_env "$dest" "$tmp/manifest.json"
  elif [[ "$kind" == upstream ]]; then
    local ver="${release#v}"
    dest="$KERNELS/upstream/$ver/$arch/$profile"
    if [[ -e "$dest" ]]; then
      (( force == 1 )) || die "destination already exists: $dest (use --force to replace)"
      rm -rf "$dest"
    fi
    mkdir -p "$dest/source" "$dest/build"
    printf 'new-upstream\n' >"$dest/new-sentinel"
  else
    die badkind
  fi
  printf 'manifest\n' >"$dest/klab-manifest.json"
  printf '%s\n' "$dest"
}
FIX
python3 "$ROOT/apply-atomic-target-import.py" "$T/klab-bundle.sh" >/dev/null
bash -n "$T/klab-bundle.sh"
mkdir -p "$T/home" "$T/final"
printf 'old\n' >"$T/final/old-sentinel"
export TEST_HOME="$T/home" TEST_DEST="$T/final"
# Failure after new target staging must leave old target untouched.
if FAIL_FIXUP=1 bash -c 'source "$1"; cmd_import_legacy fake --force' _ "$T/klab-bundle.sh" >/dev/null 2>&1; then
  echo 'FAIL: synthetic import failure unexpectedly succeeded' >&2; exit 1
fi
[[ -f "$T/final/old-sentinel" ]] || { echo 'FAIL: failed import destroyed old target' >&2; exit 1; }
[[ ! -f "$T/final/new-sentinel" ]] || { echo 'FAIL: partial target leaked into final destination' >&2; exit 1; }
# Success must atomically replace old target.
bash -c 'source "$1"; cmd_import_legacy fake --force' _ "$T/klab-bundle.sh" >/dev/null
[[ -f "$T/final/new-sentinel" ]] || { echo 'FAIL: successful import was not committed' >&2; exit 1; }
[[ ! -f "$T/final/old-sentinel" ]] || { echo 'FAIL: old target survived successful replacement' >&2; exit 1; }
! find "$T" -name '*.klab-import.*' -o -name '*.klab-old.*' | grep -q . || { echo 'FAIL: atomic import left staging directories' >&2; find "$T" -name '*.klab-*' >&2; exit 1; }
echo 'atomic-target-import: PASS'
