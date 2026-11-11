#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for x in gcc readelf; do command -v "$x" >/dev/null || { echo "SKIP: $x missing"; exit 0; }; done
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
cat >"$t/m.c" <<'EOF'
extern int external_symbol(const char *);
int f(void){ return external_symbol("x"); }
EOF
gcc -fno-pic -fno-PIE -c "$t/m.c" -o "$t/m.ko"
if ! readelf -rW "$t/m.ko" | grep -q R_X86_64_PLT32; then echo 'SKIP: host assembler does not emit R_X86_64_PLT32'; exit 0; fi
mkdir -p "$t/old/arch/x86/kernel" "$t/new/arch/x86/kernel"
printf 'case R_X86_64_PC32: break;\n' >"$t/old/arch/x86/kernel/module.c"
printf 'case R_X86_64_PC32: case R_X86_64_PLT32: break;\n' >"$t/new/arch/x86/kernel/module.c"
if "$ROOT/klab-vintage-validate.sh" --module "$t/m.ko" --arch x86_64 --kernel-release 4.10.0 --kernel-source "$t/old" >/dev/null 2>&1; then
  echo 'FAIL: source-backed validator accepted unsupported PLT32'; exit 1
fi
"$ROOT/klab-vintage-validate.sh" --module "$t/m.ko" --arch x86_64 --kernel-release 4.10.0 --kernel-source "$t/new" >/dev/null
set +e
"$ROOT/klab-vintage-validate.sh" --module "$t/m.ko" --arch x86_64 --kernel-release 4.10.0 --binutils-version 2.32 --strict-vintage >/dev/null
rc=$?
set -e
[[ "$rc" == 2 ]] || { echo "FAIL: expected strict unproven rc=2, got $rc"; exit 1; }
echo 'PASS: vintage relocation validator distinguishes source-backed support from unproven vintage hazards'
