#!/usr/bin/env bash
set -euo pipefail
SELF="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
D="$SELF/examples/multiguest/mixed-matrix-r16"
PLAN="$SELF/lib/multiguest_plan.py"
python3 - "$D/matrix.json" "$SELF" <<'PY'
import json,sys,re,os
m=json.load(open(sys.argv[1])); root=sys.argv[2]
k=m["kernel_variants"]
assert k["policy"]=="representative-cohorts-v1"
assert len(k["stable"])==12
assert set(k["cohorts"])=={"old","middle","modern"}
for arch, selected in k["versions_by_arch"].items():
    txt=open(os.path.join(root,"architectures",arch+".conf")).read()
    defaults=re.search(r"E2E_DEFAULT_VERSIONS='([^']+)'",txt).group(1).split()
    assert len(selected)==3
    assert all(v in defaults for v in selected),(arch,selected,defaults)
PY
for rel in $(python3 - "$D/matrix.json" <<'PY'
import json,sys
for x in json.load(open(sys.argv[1]))["kernel_variants"]["stable"]: print(x)
PY
); do
 "$PLAN" validate "$D/kernel-variants/$rel" >/dev/null
 python3 - "$D/kernel-variants/$rel" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
assert s["matrix"]["kernel_cohort"] in {"old","middle","modern"}
assert set(s["matrix"]["kernel_versions"])=={"client","router","server"}
for g in s["guests"]:
 assert g["target"]=="upstream:"+s["matrix"]["kernel_versions"][g["id"]]
PY
done
grep -q 'KLAB_R16_KERNEL_MATRIX:-1' "$SELF/klab-fault-overnight-r16.sh"
echo "PASS r16 kernel-version matrix"
