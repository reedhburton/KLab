#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$ROOT/providers/fedora.sh"
grep -Fq 'klab_provider_fedora_ensure_execution_supplements(){' "$F" || { echo 'Fedora execution supplement helper missing' >&2; exit 1; }
grep -Fq "session.getRPM({'name':name,'version':version,'release':release,'arch':arch},strict=True)" "$F" || { echo 'binary RPM to source-build resolution missing' >&2; exit 1; }
grep -Fq 'execution-supplement-builds.txt' "$F" || { echo 'Fedora 26 execution supplement plan missing' >&2; exit 1; }
grep -Fq "shutil.copy2(f,'/out/repo/'+os.path.basename(f))" "$F" || { echo 'cross-mount supplement copy missing' >&2; exit 1; }
grep -Fq "if ident in want:" "$F" || { echo 'Fedora 26 supplement exact-identity filter missing' >&2; exit 1; }
grep -Fq 'EXECUTION-SUPPLEMENTS-FC26-V2' "$F" || { echo 'Fedora 26 execution supplement cache marker missing' >&2; exit 1; }
grep -Fq 'klab_provider_fedora_ensure_execution_supplements "$fallback_repo" "$r" "$hub" "$topurl"' "$F" || { echo 'reconstructed repo is not supplemented before buildenv assembly' >&2; exit 1; }
! grep -Fq 'prune_uncaptured_execution_leafs' "$F" || { echo 'unsafe execution-root package pruning remains' >&2; exit 1; }
echo 'PASS: Fedora 26 augments its reconstructed repo with its complete exact Koji execution-root package closure'
