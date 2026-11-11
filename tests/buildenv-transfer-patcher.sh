#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat >"$T/klab-bundle.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR=/tmp
LAB_HOME=/tmp/lab
KERNEL_LAB_BIN="$SELF_DIR/kernel-lab.sh"
json_get(){ :; }
quote_env(){ printf '%q' "$1"; }
write_manifest(){ :; }
cmd_create_legacy() {
 local stage=/tmp/stage
 write_manifest "$stage/manifest.json" x
 add_checksum_line "$stage" manifest.json
}
cmd_import_legacy() {
 local file="$1" tmp=/tmp/x kind target provider release krel profile arch dest
 verify_stage "$tmp"
 provider=x; release=x; krel=x; arch=x86_64; kind=distro
 if [[ "$kind" == distro ]]; then
   dest=/tmp/d
   if [[ -e "$dest" ]]; then rm -rf "$dest"; fi
 fi
}
fixup_distro_env() {
 local dest="$1" manifest="$2" provider=x release=x krel=x arch=x86_64 build_image=x build=x modules=x
 cat > "$dest/bundle.env" <<EOFENV
BUNDLE_PROVIDER=$(quote_env "$provider")
EOFENV
}
EOF
python3 "$ROOT/apply-buildenv-transfer.py" "$T/klab-bundle.sh" >/dev/null
bash -n "$T/klab-bundle.sh"
grep -q "m\['buildenv'\]" "$T/klab-bundle.sh"
grep -q 'preflight thin buildenv dependencies' "$T/klab-bundle.sh"
grep -q 'assert-installed' "$T/klab-bundle.sh"
grep -q 'BUNDLE_BUILDENV_ID=' "$T/klab-bundle.sh"
echo 'buildenv-transfer-patcher: PASS'
