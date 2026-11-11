#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat >"$T/klab-bundle.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR=/tmp
KERNEL_LAB_BIN="$SELF_DIR/kernel-lab.sh"
detect_toolchain_cc(){ echo "$1/bin/gcc"; }
probe_toolchain_json(){ echo '{}'; }
sha256_file(){ echo deadbeef; }
json_get(){ :; }
quote_env(){ printf '%q' "$1"; }
cmd_create_legacy(){
 local toolchain=/tmp/tc toolchain_id=x toolchain_cc= stage=/tmp/stage toolchain_json
 if [[ -n "$toolchain" ]]; then
    say "Packing toolchain $(basename "$toolchain")"
    tar -C "$toolchain" --zstd -cf "$stage/extras/toolchain.tar.zst" .
    local tsha; tsha="$(sha256_file "$stage/extras/toolchain.tar.zst")"
    toolchain_json="$(probe_toolchain_json "$toolchain" "$tsha" "$toolchain_id" "$toolchain_cc")"
    add_checksum_line "$stage" extras/toolchain.tar.zst
 fi
}
cmd_import_legacy(){
 local tmp=/tmp/t dest=/tmp/d force=0
 if [[ -f "$tmp/extras/toolchain.tar.zst" ]]; then
    local tc_id tc_sha tc_cc_rel tc_family tc_version tc_target tc_prefix_rel tc_bin_rel tc_dest
    tc_id="$(json_get "$tmp/manifest.json" toolchain.id 2>/dev/null || true)"
    tc_sha="$(json_get "$tmp/manifest.json" toolchain.sha256)"
    tc_cc_rel="$(json_get "$tmp/manifest.json" toolchain.cc_relpath 2>/dev/null || true)"
    tc_family="$(json_get "$tmp/manifest.json" toolchain.family 2>/dev/null || true)"
    tc_version="$(json_get "$tmp/manifest.json" toolchain.version 2>/dev/null || true)"
    tc_target="$(json_get "$tmp/manifest.json" toolchain.target 2>/dev/null || true)"
    tc_prefix_rel="$(json_get "$tmp/manifest.json" toolchain.cross_prefix_relpath 2>/dev/null || true)"
    tc_bin_rel="$(json_get "$tmp/manifest.json" toolchain.bin_dir_relpath 2>/dev/null || true)"
    tc_dest=/tmp/tc
    [[ -x "$tc_dest/$tc_cc_rel" ]] || die "bound compiler missing after import: $tc_dest/$tc_cc_rel"
    cat >> "$dest/bundle.env" <<EOFENV
BUNDLE_TOOLCHAIN_ARCHIVE_SHA256=$(quote_env "$tc_sha")
EOFENV
 fi
}
EOF
cat >"$T/kernel-lab.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
SELF_DIR=/tmp
BUNDLE_BIN="$SELF_DIR/klab-bundle.sh"
reset_bundle_toolchain_vars(){ unset BUNDLE_TOOLCHAIN_BIN_DIR BUNDLE_TOOLCHAIN_ARCHIVE_SHA256; }
compiler_identity(){ :; }
prepare_bound_toolchain() {
 KLAB_TC_PATH="$PATH"; KLAB_TC_MAKE_ARGS=(); [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 ]] || return 0
 local cc="${BUNDLE_TOOLCHAIN_CC:-}" overridden=0 marker=""
 [[ -n "$cc" ]] || return 1
 if (( overridden == 0 )); then :; fi
 compiler_identity "$cc"
}
EOF
python3 "$ROOT/apply-toolchain-boundary.py" "$T/klab-bundle.sh" "$T/kernel-lab.sh" >/dev/null
bash -n "$T/klab-bundle.sh"; bash -n "$T/kernel-lab.sh"
grep -q 'KLAB_TOOLCHAIN_BOUNDARY_M2' "$T/klab-bundle.sh"
grep -q 'tree_sha256' "$T/klab-bundle.sh"
grep -q 'BUNDLE_TOOLCHAIN_TREE_SHA256' "$T/klab-bundle.sh"
grep -q 'KLAB_TOOLCHAIN_RUNTIME_BOUNDARY_M2' "$T/kernel-lab.sh"
grep -q '__tc_guard=(verify' "$T/kernel-lab.sh"
echo 'toolchain-boundary-patcher: PASS'
