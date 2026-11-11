#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
[[ $# -ge 1 && $# -le 2 ]] || { echo "usage: $0 TRANSFER_DIR [INDEX.tsv]" >&2; exit 2; }
repo="$(cd "$1" && pwd)"; out="${2:-$repo/INDEX.tsv}"
printf 'target\tarchitecture\tbytes\tsha256\tfile\n' >"$out"
while IFS= read -r -d '' f; do
  info="$($SELF/klab inspect "$f")"
  target="$(printf '%s\n' "$info" | sed -n 's/^Target:[[:space:]]*//p' | head -n1)"
  arch="$(printf '%s\n' "$info" | sed -n 's/^Architecture:[[:space:]]*//p' | head -n1)"
  bytes="$(stat -c %s "$f")"; sha="$(sha256sum "$f" | awk '{print $1}')"
  printf '%s\t%s\t%s\t%s\t%s\n' "$target" "$arch" "$bytes" "$sha" "${f#"$repo"/}" >>"$out"
done < <(find "$repo" -type f -name '*.klab' -not -path "$repo/.klab-releases/*" -print0 | LC_ALL=C sort -z)
{ head -n1 "$out"; tail -n +2 "$out" | LC_ALL=C sort; } >"$out.tmp"; mv "$out.tmp" "$out"
sha256sum "$out" >"$out.sha256"
echo "Indexed $(($(wc -l <"$out")-1)) targets in $out"
