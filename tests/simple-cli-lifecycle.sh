#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq 'build-user) shift; klab_simple_build_user "$@"' "$ROOT/klab"
grep -Fq 'start) shift; klab_simple_start "$@"' "$ROOT/klab"
grep -Fq 'validate) shift; exec "$KLAB_SELF_DIR/klab-image-validate.sh" "$@"' "$ROOT/klab"
grep -Fq 'ps) shift; exec "$KLAB_RUNNER" sessions "$@"' "$ROOT/klab"
grep -Fq 'shell) shift; exec "$KLAB_RUNNER" ssh "$@"' "$ROOT/klab"
grep -Fq '"$KLAB_RUNNER" build-module "$target" --module "$module" "$@"' "$ROOT/lib/simple-cli.sh"
grep -Fq '"$KLAB_RUNNER" build-user "$target" --source "$source" "$@"' "$ROOT/lib/simple-cli.sh"
grep -Fq 'exec "$KLAB_RUNNER" build "$@"' "$ROOT/klab"
grep -Fq 'if [[ "$source" == --source ]]' "$ROOT/lib/simple-cli.sh"
echo 'simple CLI lifecycle aliases: PASS'
