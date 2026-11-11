#!/usr/bin/env python3
import json
import os
import sys

if len(sys.argv) != 5:
    raise SystemExit("usage: scenario_retarget.py TEMPLATE OUTPUT TARGET ARCH")
src, out, target, arch = sys.argv[1:]
base = os.path.dirname(os.path.abspath(src))
with open(src, encoding="utf-8") as f:
    scenario = json.load(f)
scenario["target"] = target
scenario["arch"] = arch
for collection, field in (("builds", "source"), ("modules", "source_dir"), ("files", "source")):
    for item in scenario.get(collection, []):
        value = item.get(field)
        if isinstance(value, str) and value and not os.path.isabs(value):
            item[field] = os.path.normpath(os.path.join(base, value))
with open(out, "w", encoding="utf-8") as f:
    json.dump(scenario, f, indent=2)
    f.write("\n")
