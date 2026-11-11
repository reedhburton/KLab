#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/variants"
cat >"$T/klab" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == inspect ]]
case "$2" in
  */nested.klab) printf 'Target: ubuntu:24.04:6.8-test\nArchitecture: x86_64\n' ;;
  *) printf 'Target: upstream:v6.8\nArchitecture: x86_64\n' ;;
esac
EOF
chmod +x "$T/klab"
cp "$ROOT/beta-tools/index-repository.sh" "$T/index-repository.sh"
sed -i 's#SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"#SELF="'"$T"'"#' "$T/index-repository.sh"
: >"$T/repo/root.klab"
: >"$T/repo/variants/nested.klab"
"$T/index-repository.sh" "$T/repo" >/dev/null
grep -Fq $'ubuntu:24.04:6.8-test\tx86_64\t0\t' "$T/repo/INDEX.tsv"
grep -Fq $'\tvariants/nested.klab' "$T/repo/INDEX.tsv"
[[ $(wc -l <"$T/repo/INDEX.tsv") -eq 3 ]]
echo 'repository-recursive-index: PASS'
