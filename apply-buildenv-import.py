#!/usr/bin/env python3
from pathlib import Path
import shutil,sys,time
p=Path(sys.argv[1] if len(sys.argv)>1 else 'kernel-lab.sh')
if not p.is_file(): raise SystemExit(f'not found: {p}')
s=p.read_text()
if 'KLAB_BUILDENV_IMPORT_M2' in s: raise SystemExit('buildenv import M2 already applied')
b=p.with_name(p.name+f'.pre-buildenv-import-m2-{int(time.time())}'); shutil.copy2(p,b)
start=s.find('cmd_import_bundle() {')
if start<0: raise SystemExit('cmd_import_bundle not found')
brace=s.find('\n',start)
ins=r'''
  # KLAB_BUILDENV_IMPORT_M2: install shared buildenvs before thin target bundles.
  # Only --force applies to buildenv objects; target-only flags such as
  # --load-image must never leak into the typed buildenv importer.
  if [[ $# -ge 1 && -d "$1" ]]; then
    local __be __be_force=""
    local __arg
    for __arg in "${@:2}"; do [[ "$__arg" == --force ]] && __be_force=--force; done
    while IFS= read -r -d '' __be; do
      if [[ -n "$__be_force" ]]; then KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" import "$__be" --force >/dev/null
      else KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" import "$__be" >/dev/null; fi
    done < <(find "$1" -maxdepth 1 -type f -name '*.klabbuildenv' -print0 | sort -z)
  elif [[ $# -ge 1 && "$1" == *.klabbuildenv ]]; then
    local __be_force="" __arg
    for __arg in "${@:2}"; do
      case "$__arg" in --force) __be_force=--force ;; --load-image) : ;; *) die "unknown .klabbuildenv import option '$__arg'" ;; esac
    done
    if [[ -n "$__be_force" ]]; then KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" import "$1" --force
    else KLAB_HOME="$LAB_HOME" "$BUILDENV_BIN" import "$1"; fi
    return
  fi
'''
s=s[:brace+1]+ins+s[brace+1:]
p.write_text(s)
print(f'patched: {p}\nbackup:  {b}')
