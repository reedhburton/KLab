#!/usr/bin/env python3
from pathlib import Path
import re, shutil, sys, time
p=Path(sys.argv[1] if len(sys.argv)>1 else 'klab-bundle.sh')
if not p.is_file(): raise SystemExit(f'not found: {p}')
s=p.read_text()
if 'KLAB_BUILDENV_TRANSFER_M2' in s: raise SystemExit('buildenv transfer M2 already applied')
b=p.with_name(p.name+f'.pre-buildenv-transfer-m2-{int(time.time())}'); shutil.copy2(p,b)
# Give the bundle helper a direct verifier for installed shared buildenv objects.
anchor=re.search(r'^(KERNEL_LAB_BIN=.*)$',s,re.M)
if not anchor: raise SystemExit('KERNEL_LAB_BIN assignment not found')
s=s[:anchor.end()]+'\nBUILDENV_BIN="${KLAB_BUILDENV_BIN:-$SELF_DIR/klab-buildenv.sh}" # KLAB_BUILDENV_TRANSFER_M2'+s[anchor.end():]
# Add buildenv reference to manifest after normal manifest generation but before checksum.
# Verify the exact target->buildenv binding before export so stale bundle.env state
# cannot produce a valid-looking target that points at a different kernel build root.
m=re.search(r'^[ \t]*add_checksum_line "\$stage" manifest\.json[ \t]*$',s,re.M)
if not m: raise SystemExit('manifest checksum marker not found')
pos=m.start()
mut=r'''  # KLAB_BUILDENV_TRANSFER_M2: thin target references the shared buildenv by content ID.
  if [[ -n "${BUNDLE_BUILDENV_ID:-}" ]]; then
    local __be_provider __be_release __be_krel __be_arch __be_json
    __be_provider="$(json_get "$stage/manifest.json" provider)"
    __be_release="$(json_get "$stage/manifest.json" release)"
    __be_krel="$(json_get "$stage/manifest.json" kernel_release)"
    __be_arch="$(json_get "$stage/manifest.json" arch)"
    __be_json="$(KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" assert-installed "$BUNDLE_BUILDENV_ID" \
      --provider "$__be_provider" --release "$__be_release" --kernel-release "$__be_krel" --target-arch "$__be_arch" --json)"
    python3 - "$stage/manifest.json" "$BUNDLE_BUILDENV_ID" "$__be_json" <<'PY_BUILDENV_REF'
import json,sys
p,i,b=sys.argv[1:]
m=json.load(open(p)); be=json.loads(b)
m['buildenv']={
  'type':'buildenv','id':i,'extension':'.klabbuildenv',
  'provider':be.get('provider'),'release':be.get('release'),
  'kernel_release':be.get('kernel_release'),'target_arch':be.get('target_arch'),
  'exec_arch':be.get('exec_arch'),'root_tree_sha256':be.get('root_tree_sha256'),
  'toolchain_tree_sha256':be.get('toolchain_tree_sha256') or None,
}
with open(p,'w') as f: json.dump(m,f,indent=2,sort_keys=True); f.write('\n')
PY_BUILDENV_REF
  fi
'''
s=s[:pos]+mut+s[pos:]
# Preflight the dependency immediately after the .klab itself is verified, before
# any existing target directory is removed or payload is extracted.
imp=s.find('cmd_import_legacy() {')
if imp<0: raise SystemExit('cmd_import_legacy not found')
ver=re.search(r'^[ \t]*verify_stage "\$tmp"[ \t]*$',s[imp:],re.M)
if not ver: raise SystemExit('cmd_import_legacy verify_stage marker not found')
vpos=imp+ver.end()
preflight=r'''

  # KLAB_BUILDENV_TRANSFER_M2: preflight thin buildenv dependencies before
  # touching an existing target installation. This makes failed imports
  # non-destructive and rejects valid-but-wrong buildenv references.
  local __be_pre_id="" __be_pre_provider="" __be_pre_release="" __be_pre_krel="" __be_pre_arch="" __be_pre_tc=""
  __be_pre_id="$(json_get "$tmp/manifest.json" buildenv.id 2>/dev/null || true)"
  if [[ -n "$__be_pre_id" ]]; then
    __be_pre_provider="$(json_get "$tmp/manifest.json" provider)"
    __be_pre_release="$(json_get "$tmp/manifest.json" release)"
    __be_pre_krel="$(json_get "$tmp/manifest.json" kernel_release)"
    __be_pre_arch="$(json_get "$tmp/manifest.json" arch)"
    __be_pre_tc="$(json_get "$tmp/manifest.json" buildenv.toolchain_tree_sha256 2>/dev/null || true)"
    local __be_assert=(assert-installed "$__be_pre_id" --provider "$__be_pre_provider" --release "$__be_pre_release" --kernel-release "$__be_pre_krel" --target-arch "$__be_pre_arch" --exec-arch "$(uname -m)")
    [[ -n "$__be_pre_tc" ]] && __be_assert+=(--toolchain-tree-sha256 "$__be_pre_tc")
    KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" "${__be_assert[@]}" >/dev/null
  fi
'''
s=s[:vpos]+preflight+s[vpos:]
# During distro env reconstruction, bind the already-preflighted warehouse
# object. Reverify integrity here as a cheap race/tamper guard.
fix=s.find('fixup_distro_env() {')
if fix<0: raise SystemExit('fixup_distro_env not found')
mcat=re.search(r'^[ \t]*cat > "\$dest/bundle\.env" <<EOF[^\n]*$',s[fix:],re.M)
if not mcat: raise SystemExit('bundle.env generation not found')
catpos=fix+mcat.start()
pre=r'''  local buildenv_id="" buildenv_dir=""
  buildenv_id="$(json_get "$manifest" buildenv.id 2>/dev/null || true)"
  if [[ -n "$buildenv_id" ]]; then
    buildenv_dir="$LAB_HOME/artifacts/objects/sha256/$buildenv_id"
    KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" assert-installed "$buildenv_id" \
      --provider "$provider" --release "$release" --kernel-release "$krel" --target-arch "$arch" --exec-arch "$(uname -m)" >/dev/null
  fi
'''
s=s[:catpos]+pre+s[catpos:]
# Append fields immediately after the distro bundle.env here-doc.
end=s.find('EOFENV',catpos+len(pre))
if end<0: raise SystemExit('bundle.env EOF not found')
endline=s.find('\n',end)
append=r'''
  if [[ -n "$buildenv_id" ]]; then
    cat >> "$dest/bundle.env" <<EOF_BUILDENV
BUNDLE_BUILDENV_ID=$(quote_env "$buildenv_id")
BUNDLE_BUILDENV_DIR=$(quote_env "$buildenv_dir")
EOF_BUILDENV
  fi
'''
s=s[:endline+1]+append+s[endline+1:]
p.write_text(s)
print(f'patched: {p}\nbackup:  {b}')
