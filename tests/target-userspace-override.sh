#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
f="$ROOT/kernel-lab.sh"
grep -Fq 'use_bound=1' "$f"
grep -Fq 'use_bound=0' "$f"
grep -Fq 'The explicit --userspace request is authoritative' "$f"
grep -Fq '[[ -n "$bound" && "$bound" == "$resolved" ]]' "$f"
grep -Fq 'A prior native userspace may contain read-only directories and files.' "$f"
grep -Fq 'chmod -R u+w "$root"' "$f"
! grep -Fq 'Re-prepare the target with that userspace instead of silently substituting it.' "$f"
bash -n "$f"
echo 'PASS: explicit verified local userspace selection overrides a bundle auto default'
