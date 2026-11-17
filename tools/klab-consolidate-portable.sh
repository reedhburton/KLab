#!/usr/bin/env bash
set -Eeuo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
REPO="${KLAB_REPO:-/mnt/klab-store/klab-offline}"
EXPORTS="${KLAB_EXPORTS:-/mnt/klab-cache/exports}"
SOURCE="${KLAB_SOURCE_RELEASE:-klab-portable-reconcile-2026-11-16}"
RELEASE="${KLAB_COMPLETE_RELEASE:-klab-portable-complete-2026-11-17}"
RUN="${KLAB_CONSOLIDATE_RUN:-/mnt/klab-store/klab-data/results/portable-complete-2026-11-17}"
mkdir -p "$RUN" "$EXPORTS"
printf 'phase=starting\nstarted_utc=%s\n' "$(date -u +%FT%TZ)" > "$RUN/status"
if [[ ! -f "$REPO/.klab-releases/snapshots/$RELEASE.json" ]]; then
  python3 "$SELF/tools/klab-repo-release.py" squash "$REPO" "$SOURCE" "$RELEASE" > "$RUN/squash.log"
fi
printf 'phase=exporting\nstarted_utc=%s\n' "$(date -u +%FT%TZ)" > "$RUN/status"
archive="$EXPORTS/$RELEASE.tar.zst"
python3 "$SELF/tools/klab-repo-release.py" export "$REPO" "$RELEASE" -o "$archive" > "$RUN/export.log"
printf 'phase=verifying\nstarted_utc=%s\n' "$(date -u +%FT%TZ)" > "$RUN/status"
(cd "$EXPORTS" && sha256sum -c "$(basename "$archive.sha256")") > "$RUN/verify.log"
bytes="$(stat -c %s "$archive")"; sha="$(awk '{print $1}' "$archive.sha256")"
printf 'phase=complete\nfinished_utc=%s\narchive=%s\nbytes=%s\nsha256=%s\n' "$(date -u +%FT%TZ)" "$archive" "$bytes" "$sha" > "$RUN/status"
