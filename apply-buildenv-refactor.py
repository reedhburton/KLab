#!/usr/bin/env python3
from pathlib import Path
import re, shutil, sys, time

p=Path(sys.argv[1] if len(sys.argv)>1 else 'kernel-lab.sh')
if not p.is_file(): raise SystemExit(f'not found: {p}')
s=p.read_text()
if 'KLAB_BUILDENV_M2' in s: raise SystemExit('buildenv M2 already applied')
b=p.with_name(p.name+f'.pre-buildenv-m2-{int(time.time())}'); shutil.copy2(p,b)

m=re.search(r'^(BUNDLE_BIN=.*)$',s,re.M)
if not m: raise SystemExit('BUNDLE_BIN assignment not found')
s=s[:m.end()]+'\nBUILDENV_BIN="${KLAB_BUILDENV_BIN:-$SELF_DIR/klab-buildenv.sh}" # KLAB_BUILDENV_M2'+s[m.end():]

needle='cmd_fetch "$target" >/dev/null'
pos=s.find(needle)
if pos<0: raise SystemExit('cmd_prepare distro fetch marker not found')
insert=r'''
    # KLAB_BUILDENV_M2: capture an exact provider build root, but first resolve
    # and seal the toolchain that will be packaged with this target. The
    # .klabbuildenv stores the expected toolchain tree digest independently.
    case "${provider:-${target%%:*}}" in
      ubuntu|debian|fedora|centos|rhel|rocky|almalinux)
        if [[ "${tc_mode:-auto}" == none ]]; then
          say "Toolchain disabled; skipping hermetic .klabbuildenv capture for $target"
        else
          parse_target "$target"
          local __be_bundle __be_dir __be_file __be_id __be_tc_dir __be_tc_cc __be_tc_rel __be_tc_json __be_guard
          local __be_tc_tree __be_tc_family __be_tc_version __be_tc_target
          if [[ "${tc_mode:-auto}" == manual ]]; then
            __be_tc_dir="$(readlink -f "$tc_dir")"
          else
            __be_tc_dir="$(KLAB_HOME="$LAB_HOME" KLAB_ARCH="${ARCH:-x86_64}" "$0" toolchain ensure "$target" "$profile")"
            tc_mode=manual
            tc_dir="$__be_tc_dir"
          fi
          [[ -d "$__be_tc_dir" ]] || die "resolved toolchain directory missing: $__be_tc_dir"
          __be_tc_cc=''
          if [[ -f "$__be_tc_dir/.klab-resolver.env" ]]; then
            unset KLAB_TOOLCHAIN_CC
            # shellcheck disable=SC1090
            source "$__be_tc_dir/.klab-resolver.env"
            __be_tc_cc="${KLAB_TOOLCHAIN_CC:-}"
          fi
          if [[ -z "$__be_tc_cc" || "$__be_tc_cc" != "$__be_tc_dir"/* ]]; then
            __be_tc_cc="$(find "$__be_tc_dir" -maxdepth 8 \( -type f -o -type l \) -perm -111 \( -name '*-gcc' -o -name gcc \) -print 2>/dev/null | sort | head -n1 || true)"
          fi
          [[ -n "$__be_tc_cc" && -x "$__be_tc_cc" ]] || die "could not locate GCC inside toolchain $__be_tc_dir"
          __be_tc_rel="${__be_tc_cc#"$__be_tc_dir"/}"
          __be_guard="${KLAB_TOOLCHAIN_BOUNDARY_BIN:-$SELF_DIR/klab-toolchain-boundary.sh}"
          [[ -x "$__be_guard" ]] || die "toolchain boundary helper missing: $__be_guard"
          __be_tc_json="$("$__be_guard" seal --root "$__be_tc_dir" --cc "$__be_tc_rel" --json)"
          IFS=$'\t' read -r __be_tc_tree __be_tc_family __be_tc_version __be_tc_target < <(python3 - "$__be_tc_json" <<'PY_BE_TC'
import json,sys
m=json.loads(sys.argv[1])
print('\t'.join(str(m.get(k,'')) for k in ('tree_sha256','family','version','target')))
PY_BE_TC
          )
          [[ -n "$__be_tc_tree" ]] || die "toolchain sealing produced no tree digest"
          __be_bundle="$(bundle_existing_dir_for "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "${ARCH:-x86_64}")"
          __be_dir="${artifact_dir:-$(dirname "$output")}"; mkdir -p "$__be_dir"
          __be_file="$__be_dir/buildenv-${PROVIDER}-${KERNEL_RELEASE}-${ARCH}--pending.klabbuildenv"
          KLAB_BUILDENV_TOOLCHAIN_ROOT="$__be_tc_dir" KLAB_BUILDENV_TOOLCHAIN_JSON="$__be_tc_json" \
            KLAB_BUILDENV_TOOLCHAIN_TREE_SHA256="$__be_tc_tree" KLAB_BUILDENV_TOOLCHAIN_FAMILY="$__be_tc_family" \
            KLAB_BUILDENV_TOOLCHAIN_VERSION="$__be_tc_version" KLAB_BUILDENV_TOOLCHAIN_TARGET="$__be_tc_target" \
            KLAB_BUILDENV_TOOLCHAIN_CC_REL="$__be_tc_rel" \
            klab_provider_capture_buildenv "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$__be_bundle" "$__be_file" "$ARCH" >/dev/null
          __be_id="$($BUILDENV_BIN verify "$__be_file" --deep)"
          local __be_final="$__be_dir/buildenv-${PROVIDER}-${KERNEL_RELEASE}-${ARCH}--${__be_id:0:16}.klabbuildenv"
          mv -f "$__be_file" "$__be_final"
          KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" import "$__be_final" >/dev/null
          { grep -v '^BUNDLE_BUILDENV_' "$__be_bundle/bundle.env" 2>/dev/null || true; } >"$__be_bundle/bundle.env.tmp"
          printf 'BUNDLE_BUILDENV_ID=%q\nBUNDLE_BUILDENV_FILE=%q\n' "$__be_id" "$__be_final" >>"$__be_bundle/bundle.env.tmp"
          mv "$__be_bundle/bundle.env.tmp" "$__be_bundle/bundle.env"
        fi
        ;;
    esac
'''
s=s[:pos+len(needle)]+insert+s[pos+len(needle):]

base=s.find('build_external_module_bundle() {')
m=re.search(r'^[ \t]*say "Building module for \$target in isolated job \$\(basename "\$job"\)"[ \t]*$',s[base:],re.M) if base >= 0 else None
if not m: raise SystemExit('build_external_module_bundle insertion point not found')
pos=base+m.end()
block=r'''

  # KLAB_BUILDENV_M2: exact distro build roots run in the captured sandbox.
  if [[ -n "${BUNDLE_BUILDENV_ID:-}" ]]; then
    [[ "${BUNDLE_TOOLCHAIN_BOUND:-0}" == 1 ]] || die "target references .klabbuildenv but has no bound .klabtoolchain"
    local __be_tc_tree="${BUNDLE_TOOLCHAIN_TREE_SHA256:-}" __be_meta=''
    if [[ -z "$__be_tc_tree" && -f "$BUNDLE_TOOLCHAIN_DIR/.klab-toolchain-boundary.json" ]]; then
      __be_tc_tree="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("tree_sha256",""))' "$BUNDLE_TOOLCHAIN_DIR/.klab-toolchain-boundary.json")"
    fi
    # Thin v16/v17 .klabtoolchain imports predate the boundary marker. The
    # .klabbuildenv already pins the exact expected toolchain tree, so recover
    # that digest from the verified installed buildenv instead of weakening the
    # boundary or requiring a new typed-toolchain archive format.
    if [[ -z "$__be_tc_tree" ]]; then
      __be_meta="$(KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" assert-installed "$BUNDLE_BUILDENV_ID" --provider "$BUNDLE_PROVIDER" --release "$BUNDLE_DISTRO_RELEASE" --kernel-release "$BUNDLE_KERNEL_RELEASE" --target-arch "${BUNDLE_ARCH:-$ARCH}" --json)"
      __be_tc_tree="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("toolchain_tree_sha256", ""))' "$__be_meta")"
    fi
    [[ -n "$__be_tc_tree" ]] || die "target references .klabbuildenv but its verified manifest does not pin a toolchain tree; recreate the target with current KLab"
    local be_args=(run-module "$BUNDLE_BUILDENV_ID" --toolchain-root "$BUNDLE_TOOLCHAIN_DIR" --toolchain-cc "$BUNDLE_TOOLCHAIN_CC_REL" --toolchain-tree-sha256 "$__be_tc_tree" --toolchain-family "${BUNDLE_TOOLCHAIN_FAMILY:-gcc}" --toolchain-version "${BUNDLE_TOOLCHAIN_VERSION:-}" --toolchain-target "${BUNDLE_TOOLCHAIN_TARGET:-}" --module "$job/module" --jobs "$JOBS" --kernel-arch "$(linux_karch "${BUNDLE_ARCH:-$ARCH}")" --expect-provider "$BUNDLE_PROVIDER" --expect-release "$BUNDLE_DISTRO_RELEASE" --expect-kernel-release "$BUNDLE_KERNEL_RELEASE" --expect-target-arch "${BUNDLE_ARCH:-$ARCH}")
    [[ -n "${BUNDLE_TOOLCHAIN_CROSS_PREFIX_REL:-}" ]] && be_args+=(--cross-prefix "$BUNDLE_TOOLCHAIN_CROSS_PREFIX_REL")
    KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" "${be_args[@]}"
    mapfile -t MODULE_FILES < <(find "$job/module" -type f -name '*.ko' -print | sort)
    ((${#MODULE_FILES[@]} > 0)) || die "no .ko files were produced for $target in buildenv $BUNDLE_BUILDENV_ID"
    MODULE_JOB="$job"
    return
  fi
'''
s=s[:pos]+block+s[pos:]

# Expose typed buildenv maintenance without making it a core dependency for
# upstream-only users. The helper owns its own doctor/list/verify semantics.
main_idx=s.rfind('main() {')
if main_idx>=0:
    dispatch='    toolchain) shift; cmd_toolchain "$@" ;;'
    dpos=s.find(dispatch,main_idx)
    if dpos>=0:
        s=s[:dpos]+'    buildenv) shift; "$BUILDENV_BIN" "$@" ;;\n'+s[dpos:]
    else:
        # v15/v17 runners may dispatch toolchain with slightly different whitespace.
        mm=re.search(r'^[ \t]*toolchain\) shift;[^\n]*$',s[main_idx:],re.M)
        if mm:
            dpos=main_idx+mm.start()
            s=s[:dpos]+'    buildenv) shift; "$BUILDENV_BIN" "$@" ;;\n'+s[dpos:]
info_marker='  if [[ -n "${BUNDLE_KERNEL_COMPILER_FAMILY:-}" ]]; then'
idx=s.find(info_marker,s.find('cmd_info() {'))
if idx>=0:
    info='''  if [[ -n "${BUNDLE_BUILDENV_ID:-}" ]]; then\n    printf 'Buildenv ID:     %s\\n' "$BUNDLE_BUILDENV_ID"\n  fi\n'''
    s=s[:idx]+info+s[idx:]
p.write_text(s)
print(f'patched: {p}\nbackup:  {b}')
