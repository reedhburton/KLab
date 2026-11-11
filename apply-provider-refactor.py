#!/usr/bin/env python3
from pathlib import Path
import re, shutil, sys, time

path = Path(sys.argv[1] if len(sys.argv) > 1 else "kernel-lab.sh")
if not path.is_file():
    raise SystemExit(f"not found: {path}")
text = path.read_text()
if "KLAB_PROVIDER_REFACTOR_M2" in text:
    raise SystemExit("provider refactor milestone 2 already applied")
backup = path.with_name(path.name + f".pre-provider-refactor-{int(time.time())}")
shutil.copy2(path, backup)

loader = '''\n# KLAB_PROVIDER_REFACTOR_M2\n# Unified provider dispatcher. Provider policy lives in providers/*.sh and\n# package-manager mechanics live in lib/backends/*.sh.\n# shellcheck disable=SC1091\nsource "$SELF_DIR/lib/provider-core.sh"\n\n'''
marker = "providers_show() {"
pos = text.find(marker)
if pos < 0:
    raise SystemExit("could not find providers_show() insertion point")
text = text[:pos] + loader + text[pos:]

# Keep providers_show stable at the CLI while moving its contents to discovery.
start = text.find("providers_show() {")
end = text.find("provider_list_apt() {", start)
if start < 0 or end < 0:
    raise SystemExit("could not locate providers_show/provider_list_apt block")
text = text[:start] + 'providers_show() { klab_provider_show; }\n\n' + text[end:]

# Replace list dispatch. Upstream and FreeBSD remain core providers for now.
start = text.find("cmd_provider_list() {")
end = text.find("extract_debs() {", start)
if start < 0 or end < 0:
    raise SystemExit("could not locate cmd_provider_list block")
new_list = r'''cmd_provider_list() {
  [[ "$OFFLINE" != 1 ]] || die "offline mode: provider listing requires network access"
  local spec="$1" pattern="${2:-}"
  [[ -z "$pattern" ]] || validate_token "$pattern" pattern
  parse_target "$spec"
  [[ -z "$KERNEL_RELEASE" ]] || die "list expects provider:release, not a kernel release"
  case "$PROVIDER" in
    upstream)
      git -C "$SRC" tag -l "v${pattern:-*}" | tail -n 200
      ;;
    freebsd)
      provider_list_freebsd "$DISTRO_RELEASE"
      ;;
    *)
      klab_provider_list "$PROVIDER" "$DISTRO_RELEASE" "$pattern"
      ;;
  esac
}

'''
text = text[:start] + new_list + text[end:]

# Replace only the distro fetch dispatch inside cmd_fetch; leave upstream and
# FreeBSD special handling intact.
fstart = text.find("cmd_fetch() {")
fend = text.find("cmd_info() {", fstart)
if fstart < 0 or fend < 0:
    raise SystemExit("could not locate cmd_fetch block")
block = text[fstart:fend]
pat = re.compile(r'''  case "\$PROVIDER" in\n    ubuntu\|debian\) fetch_apt_bundle .*?\n    fedora\) fetch_fedora_bundle .*?\n    centos\) fetch_centos_bundle .*?\n    rhel\) fetch_rhel_bundle .*?\n    \*\) die "unknown provider '\$PROVIDER'" ;;\n  esac''')
repl = '''  klab_provider_fetch "$PROVIDER" "$DISTRO_RELEASE" "$KERNEL_RELEASE" "$bundle"'''
block2, count = pat.subn(repl, block, count=1)
if count != 1:
    raise SystemExit("could not locate the expected distro fetch dispatch; backup left untouched")
text = text[:fstart] + block2 + text[fend:]

# Route connected distro module builds through the provider too. The existing
# bound-toolchain/offline fast path remains unchanged; this replaces only the
# container/provider-specific case that follows it.
bstart = text.find("build_external_module_bundle() {")
bend = text.find("make_initramfs_bundle() {", bstart)
if bstart < 0 or bend < 0:
    raise SystemExit("could not locate build_external_module_bundle block")
bblock = text[bstart:bend]
bpat = re.compile(
    r"  case \"\$provider\" in\n    ubuntu\|debian\).*?\n    \*\) die \"unsupported bundle provider '\$provider'\" ;;\n  esac",
    re.S,
)
brepl = "  klab_provider_build_module \"$provider\" \"$BUNDLE_DISTRO_RELEASE\" \\\n    \"$BUNDLE_KERNEL_RELEASE\" \"$image\" \"$BUNDLE_PACKAGES\" \"$job/module\" \"$JOBS\""
bblock2, count = bpat.subn(brepl, bblock, count=1)
if count != 1:
    raise SystemExit("could not locate connected distro module-build dispatch; backup left untouched")
text = text[:bstart] + bblock2 + text[bend:]

path.write_text(text)
print(f"patched: {path}")
print(f"backup:  {backup}")
