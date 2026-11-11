#!/usr/bin/env python3
from pathlib import Path
import re, shutil, sys, time

if len(sys.argv) < 2:
    raise SystemExit('usage: apply-toolchain-boundary.py KLAB-BUNDLE.SH [KERNEL-LAB.SH]')
bundle=Path(sys.argv[1])
runner=Path(sys.argv[2]) if len(sys.argv)>2 else None
if not bundle.is_file(): raise SystemExit(f'not found: {bundle}')

def backup(p, tag):
    b=p.with_name(p.name+f'.pre-{tag}-{int(time.time())}'); shutil.copy2(p,b); return b

def patch_bundle(p):
    s=p.read_text()
    if 'KLAB_TOOLCHAIN_BOUNDARY_M2' in s: raise SystemExit('toolchain boundary already applied to bundle helper')
    b=backup(p,'toolchain-boundary-m2')
    m=re.search(r'^(KERNEL_LAB_BIN=.*)$',s,re.M)
    if not m: raise SystemExit('KERNEL_LAB_BIN assignment not found')
    s=s[:m.end()]+'\nTOOLCHAIN_BOUNDARY_BIN="${KLAB_TOOLCHAIN_BOUNDARY_BIN:-$SELF_DIR/klab-toolchain-boundary.sh}" # KLAB_TOOLCHAIN_BOUNDARY_M2'+s[m.end():]

    # Seal before tar so the boundary metadata itself travels in standalone and
    # generic typed-artifact payloads. Merge the independent tree digest into
    # the target manifest as a second, external expectation.
    pat=re.compile(r'''(?P<ind>\s*)say "Packing toolchain \$\(basename "\$toolchain"\)"\n(?P=ind)tar -C "\$toolchain" --zstd -cf "\$stage/extras/toolchain\.tar\.zst" \.\n(?P=ind)local tsha; tsha="\$\(sha256_file "\$stage/extras/toolchain\.tar\.zst"\)"\n(?P=ind)toolchain_json="\$\(probe_toolchain_json "\$toolchain" "\$tsha" "\$toolchain_id" "\$toolchain_cc"\)"''')
    m=pat.search(s)
    if not m: raise SystemExit('toolchain packaging sequence not found')
    ind=m.group('ind')
    repl=f'''{ind}say "Packing toolchain $(basename "$toolchain")"\n{ind}local tc_cc_abs tc_cc_rel tc_boundary_json tsha\n{ind}tc_cc_abs="$(detect_toolchain_cc "$toolchain" "$toolchain_cc")"\n{ind}tc_cc_rel="${{tc_cc_abs#"$toolchain"/}}"\n{ind}tc_boundary_json="$("$TOOLCHAIN_BOUNDARY_BIN" seal --root "$toolchain" --cc "$tc_cc_rel" --json)"\n{ind}tar -C "$toolchain" --zstd -cf "$stage/extras/toolchain.tar.zst" .\n{ind}tsha="$(sha256_file "$stage/extras/toolchain.tar.zst")"\n{ind}toolchain_json="$(probe_toolchain_json "$toolchain" "$tsha" "$toolchain_id" "$toolchain_cc")"\n{ind}toolchain_json="$(python3 - "$toolchain_json" "$tc_boundary_json" <<'PY_TC_BOUNDARY_MERGE'\nimport json,sys\nt,b=map(json.loads,sys.argv[1:])\nt['tree_sha256']=b['tree_sha256']\nt['boundary_format']=b['format']\nt['boundary_version']=b['format_version']\nt['programs']=b['programs']\nprint(json.dumps(t,separators=(',',':')))\nPY_TC_BOUNDARY_MERGE\n{ind})"'''
    s=s[:m.start()]+repl+s[m.end():]

    # Inline/standalone importer: read and enforce the independent tree digest.
    localpat=re.compile(r'local tc_id tc_sha tc_cc_rel tc_family tc_version tc_target tc_prefix_rel tc_bin_rel tc_dest')
    m=localpat.search(s)
    if not m: raise SystemExit('toolchain import local declaration not found')
    s=s[:m.start()]+'local tc_id tc_sha tc_cc_rel tc_family tc_version tc_target tc_prefix_rel tc_bin_rel tc_dest tc_tree_sha tc_boundary_json'+s[m.end():]
    marker='tc_bin_rel="$(json_get "$tmp/manifest.json" toolchain.bin_dir_relpath 2>/dev/null || true)"'
    idx=s.find(marker,m.start())
    if idx<0: raise SystemExit('toolchain import metadata marker not found')
    pos=idx+len(marker)
    s=s[:pos]+'\n    tc_tree_sha="$(json_get "$tmp/manifest.json" toolchain.tree_sha256 2>/dev/null || true)"'+s[pos:]
    marker2='[[ -x "$tc_dest/$tc_cc_rel" ]] || die "bound compiler missing after import: $tc_dest/$tc_cc_rel"'
    idx=s.find(marker2,pos)
    if idx<0: raise SystemExit('post-import compiler check not found')
    pos2=idx+len(marker2)
    verify='''\n    if [[ -n "$tc_tree_sha" || -f "$tc_dest/.klab-toolchain-boundary.json" ]]; then
      local __tc_args=(verify --root "$tc_dest" --cc "$tc_cc_rel" --family "${tc_family:-gcc}")
      [[ -n "$tc_tree_sha" ]] && __tc_args+=(--tree-sha256 "$tc_tree_sha")
      [[ -n "$tc_version" ]] && __tc_args+=(--version "$tc_version")
      [[ -n "$tc_target" ]] && __tc_args+=(--target "$tc_target")
      tc_boundary_json="$("$TOOLCHAIN_BOUNDARY_BIN" "${__tc_args[@]}" --json)"
      tc_tree_sha="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["tree_sha256"])' "$tc_boundary_json")"
    fi
'''
    s=s[:pos2]+verify+s[pos2:]
    envmark='BUNDLE_TOOLCHAIN_ARCHIVE_SHA256=$(quote_env "$tc_sha")'
    idx=s.find(envmark,pos2)
    if idx<0: raise SystemExit('toolchain bundle.env archive hash field not found')
    pos3=idx+len(envmark)
    s=s[:pos3]+'\nBUNDLE_TOOLCHAIN_TREE_SHA256=$(quote_env "$tc_tree_sha")'+s[pos3:]
    p.write_text(s)
    return b

def patch_runner(p):
    s=p.read_text()
    if 'KLAB_TOOLCHAIN_RUNTIME_BOUNDARY_M2' in s: raise SystemExit('toolchain runtime boundary already applied')
    b=backup(p,'toolchain-runtime-boundary-m2')
    m=re.search(r'^(BUNDLE_BIN=.*)$',s,re.M)
    if not m: raise SystemExit('BUNDLE_BIN assignment not found in runner')
    s=s[:m.end()]+'\nTOOLCHAIN_BOUNDARY_BIN="${KLAB_TOOLCHAIN_BOUNDARY_BIN:-$SELF_DIR/klab-toolchain-boundary.sh}" # KLAB_TOOLCHAIN_RUNTIME_BOUNDARY_M2'+s[m.end():]
    # Make reset aware of the new binding field if reset function exists.
    s=s.replace('BUNDLE_TOOLCHAIN_BIN_DIR BUNDLE_TOOLCHAIN_ARCHIVE_SHA256', 'BUNDLE_TOOLCHAIN_BIN_DIR BUNDLE_TOOLCHAIN_ARCHIVE_SHA256 BUNDLE_TOOLCHAIN_TREE_SHA256')
    # Verify tree + symlink/helper boundary before compiler identity. Legacy bundles
    # with no seal keep the old behavior unless a buildenv requires the seal.
    start=s.find('prepare_bound_toolchain() {')
    if start<0: raise SystemExit('prepare_bound_toolchain not found')
    mm=re.search(r'^[ \t]*compiler_identity \"\$cc\"[ \t]*$',s[start:],re.M)
    if not mm: raise SystemExit('compiler_identity call not found in prepare_bound_toolchain')
    idx=start+mm.start()
    guard='''  if (( overridden == 0 )) && [[ -n "${BUNDLE_TOOLCHAIN_TREE_SHA256:-}" || -f "$BUNDLE_TOOLCHAIN_DIR/.klab-toolchain-boundary.json" ]]; then
    local __tc_guard=(verify --root "$BUNDLE_TOOLCHAIN_DIR" --cc "${BUNDLE_TOOLCHAIN_CC_REL:-${cc#"$BUNDLE_TOOLCHAIN_DIR"/}}" --family "${BUNDLE_TOOLCHAIN_FAMILY:-gcc}")
    [[ -n "${BUNDLE_TOOLCHAIN_TREE_SHA256:-}" ]] && __tc_guard+=(--tree-sha256 "$BUNDLE_TOOLCHAIN_TREE_SHA256")
    [[ -n "${BUNDLE_TOOLCHAIN_VERSION:-}" ]] && __tc_guard+=(--version "$BUNDLE_TOOLCHAIN_VERSION")
    [[ -n "${BUNDLE_TOOLCHAIN_TARGET:-}" ]] && __tc_guard+=(--target "$BUNDLE_TOOLCHAIN_TARGET")
    "$TOOLCHAIN_BOUNDARY_BIN" "${__tc_guard[@]}" >/dev/null
  fi

'''
    s=s[:idx]+guard+s[idx:]
    p.write_text(s)
    return b

bb=patch_bundle(bundle)
print(f'patched: {bundle}\nbackup:  {bb}')
if runner is not None:
    if not runner.is_file(): raise SystemExit(f'not found: {runner}')
    rb=patch_runner(runner)
    print(f'patched: {runner}\nbackup:  {rb}')
