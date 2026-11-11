#!/usr/bin/env python3
"""Validate and report KLab's BSD v1 release floor."""
import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("matrix", nargs="?", type=Path,
                        default=Path(__file__).resolve().parents[1] / "bsd" / "targets-v1.json")
    parser.add_argument("--check", action="store_true", help="return nonzero until every required target passes")
    args = parser.parse_args()
    data = json.loads(args.matrix.read_text())
    if data.get("schema") != "klab-bsd-matrix-v1":
        raise SystemExit("unsupported BSD matrix schema")
    levels = data["levels"]
    rank = {name: i for i, name in enumerate(levels)}
    rows = data["targets"]
    by_id = {row["id"]: row for row in rows}
    if len(by_id) != len(rows):
        raise SystemExit("duplicate BSD target id")
    required = data["policy"]["minimum_required"]
    missing = [target_id for target_id in required if target_id not in by_id]
    if missing:
        raise SystemExit("missing required targets: " + ", ".join(missing))
    failures = []
    print("ID\tTARGET\tREQUIRED\tACHIEVED\tSTATUS")
    for row in rows:
        needed = row["required_level"]
        achieved = row.get("achieved_level")
        if needed not in rank or (achieved is not None and achieved not in rank):
            raise SystemExit(f"invalid level in {row['id']}")
        passed = achieved is not None and rank[achieved] >= rank[needed]
        if row["id"] in required and not passed:
            failures.append(row["id"])
        print("\t".join((row["id"], row["target"], needed, achieved or "-", row["status"])))
    print(f"\nBSD_V1_GATE={'PASS' if not failures else 'BLOCKED'}")
    if failures:
        print("BLOCKERS=" + ",".join(failures))
    return 1 if args.check and failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
