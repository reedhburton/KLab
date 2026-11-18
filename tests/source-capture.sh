#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/tree"; printf 'all:\n' > "$T/tree/Makefile"
cat > "$T/coverage.tsv" <<EOF
target\tarch\tfamily\tstate\tlocal_target\toffline_artifact\tsources\tevidence\tsource_coverage\tsource_id\tsource_provenance\tsource_path\tbuild_path
upstream:v6.6\tx86_64\tupstream-linux\tpackaged\tyes\tyes\tlocal\t-\tfull-source\t\tupstream:v6.6\t$T/tree\t
upstream:v6.6\tarmv7\tupstream-linux\tpackaged\tyes\tyes\tlocal\t-\tfull-source\t\tupstream:v6.6\t$T/tree\t
EOF
sed -i 's/\\t/\t/g' "$T/coverage.tsv"
KLAB_ROOT="$T/root" KLAB_HOME="$T/root" python3 "$ROOT/tools/klab-capture-sources.py" --coverage "$T/coverage.tsv" --repo "$T/repo" --klab "$ROOT" --state "$T/state" >/dev/null
[[ "$(find "$T/repo/sources" -name '*.klabsource' | wc -l)" == 1 ]]
[[ "$(awk 'END{print NR-1}' "$T/repo/catalog/SOURCE_BINDINGS.tsv")" == 2 ]]
[[ "$(awk -F '\t' 'NR>1{print $4}' "$T/repo/catalog/SOURCE_BINDINGS.tsv" | sort -u | wc -l)" == 1 ]]
echo 'resumable deduplicated source capture: PASS'
