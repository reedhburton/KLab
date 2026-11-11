#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/lib/backends/apt.sh"
grep -q 'APT::Get::AllowUnauthenticated' "$f"
grep -q 'Acquire::AllowInsecureRepositories' "$f"
grep -q 'Acquire::AllowDowngradeToInsecureRepositories' "$f"
grep -q 'insecure APT authentication override is forbidden' "$f"
# Expired EOL Release metadata may still disable freshness without disabling signatures.
grep -q 'Acquire::Check-Valid-Until=false' "$ROOT/providers/ubuntu.sh"
! grep -Eq 'trusted=yes|--allow-unauthenticated' "$ROOT/providers/ubuntu.sh" "$f"
echo 'APT authentication policy regression: PASS'
