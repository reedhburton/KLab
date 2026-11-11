#!/usr/bin/env python3
from pathlib import Path
import re, shutil, sys, time

p=Path(sys.argv[1] if len(sys.argv)>1 else 'klab-bundle.sh')
if not p.is_file():
    raise SystemExit(f'not found: {p}')
s=p.read_text()
if 'KLAB_ATOMIC_TARGET_IMPORT_M2' in s:
    raise SystemExit('atomic target import M2 already applied')
b=p.with_name(p.name+f'.pre-atomic-target-import-m2-{int(time.time())}')
shutil.copy2(p,b)

start=s.find('cmd_import_legacy() {')
if start < 0:
    raise SystemExit('cmd_import_legacy not found')
if 'remove_tree() {' not in s:
    helper='''remove_tree() {
  local path="${1:-}"
  [[ -n "$path" && -e "$path" ]] || return 0
  chmod -R u+w "$path" 2>/dev/null || true
  rm -rf -- "$path"
}

'''
    s=s[:start]+helper+s[start:]
    start+=len(helper)
# Restrict rewrites to this function. Prefer the next top-level function.
next_fn=re.search(r'^}\n\n(?=[A-Za-z_][A-Za-z0-9_]*\(\) \{)', s[start:], re.M)
end=start+(next_fn.end() if next_fn else len(s)-start)
fn=s[start:end]

needle='local tmp; tmp="$(mktemp -d)"; trap "rm -rf \'$tmp\'" EXIT'
if needle not in fn:
    raise SystemExit('temporary import directory marker not found')
fn=fn.replace(needle, '''local tmp; tmp="$(mktemp -d)"
  local __atomic_final="" __atomic_tmp="" __atomic_old=""
  # KLAB_ATOMIC_TARGET_IMPORT_M2: partial imports live beside the final target
  # and are discarded on failure; the installed target is untouched until commit.
  trap "remove_tree '$tmp'; [[ -z \\\"\\${__atomic_tmp:-}\\\" ]] || remove_tree \\\"\\${__atomic_tmp}\\\"" EXIT''', 1)

# Replace the standard destructive force block. The following mkdir may create
# either $dest or $dest/source + $dest/build; both now use the temporary path.
pat=re.compile(
    r'(?P<ind>[ \t]*)if \[\[ -e "\$dest" \]\]; then\n'
    r'(?P=ind)  \(\( force == 1 \)\) \|\| die "destination already exists: \$dest \(use --force to replace\)"\n'
    r'(?P=ind)  rm -rf "\$dest"\n'
    r'(?P=ind)fi'
)

def repl(m):
    i=m.group('ind')
    return (
        f'{i}__atomic_final="$dest"\n'
        f'{i}if [[ -e "$__atomic_final" ]]; then\n'
        f'{i}  (( force == 1 )) || die "destination already exists: $__atomic_final (use --force to replace)"\n'
        f'{i}fi\n'
        f'{i}__atomic_tmp="${{__atomic_final}}.klab-import.$$"\n'
        f'{i}trap "remove_tree \'$tmp\'; remove_tree \'$__atomic_tmp\'" EXIT\n'
        f'{i}remove_tree "$__atomic_tmp"\n'
        f'{i}dest="$__atomic_tmp"'
    )

fn,n=pat.subn(repl,fn)
if n < 2:
    raise SystemExit(f'expected at least two Linux destination blocks, patched {n}')

# Commit after every target-local/shared-artifact fixup has succeeded.
prints=list(re.finditer(r'^[ \t]*printf \'%s\\n\' "\$dest"[ \t]*$', fn, re.M))
if not prints:
    raise SystemExit('final imported destination print not found')
pos=prints[-1].start()
commit='''  # KLAB_ATOMIC_TARGET_IMPORT_M2: commit the fully assembled target. If the
  # final rename fails after moving the previous target aside, restore it.
  if [[ -n "$__atomic_final" ]]; then
    if [[ -e "$__atomic_final" ]]; then
      __atomic_old="${__atomic_final}.klab-old.$$"
      remove_tree "$__atomic_old"
      mv -- "$__atomic_final" "$__atomic_old" || die "could not stage existing target for atomic replacement: $__atomic_final"
    fi
    if ! mv -- "$dest" "$__atomic_final"; then
      [[ -z "$__atomic_old" || ! -e "$__atomic_old" ]] || mv -- "$__atomic_old" "$__atomic_final" || true
      die "could not atomically install target: $__atomic_final"
    fi
    __atomic_tmp=""
    [[ -z "$__atomic_old" ]] || remove_tree "$__atomic_old"
    dest="$__atomic_final"
  fi
'''
fn=fn[:pos]+commit+fn[pos:]
s=s[:start]+fn+s[end:]
p.write_text(s)
print(f'patched: {p}\nbackup:  {b}')
