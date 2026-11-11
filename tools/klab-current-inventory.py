#!/usr/bin/env python3
"""Merge KLab's local target cache, portable bundles, and validation evidence."""
import argparse
import csv
from collections import Counter
from pathlib import Path


def rows(path):
    if not path.is_file():
        return []
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--local", required=True, type=Path)
    parser.add_argument("--bundles", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    merged = {}
    for item in rows(args.base):
        key = (item["target"], item["arch"])
        provider = key[0].split(":", 1)[0]
        family = "upstream-linux" if provider == "upstream" else (provider if provider in {"freebsd", "netbsd", "openbsd", "dragonfly"} else "linux")
        merged[key] = {
            "target": key[0], "arch": key[1], "family": family,
            "state": item["state"], "local_target": "no",
            "offline_artifact": "no", "sources": set(filter(None, item["sources"].split(","))),
            "evidence": list(filter(None, item["evidence"].split(" | "))),
        }

    physical = {}
    for item in rows(args.bundles):
        if item.get("error") or not item.get("target") or not item.get("arch"):
            continue
        physical.setdefault((item["target"], item["arch"]), []).append(item["file"])

    for item in rows(args.local):
        key = (item["target"], item["arch"])
        provider = key[0].split(":", 1)[0]
        rec = merged.setdefault(key, {
            "target": key[0], "arch": key[1],
            "family": "upstream-linux" if provider == "upstream" else (provider if provider in {"freebsd", "netbsd", "openbsd", "dragonfly"} else "linux"),
            "state": "local", "local_target": "no", "offline_artifact": "no",
            "sources": set(), "evidence": [],
        })
        rec["local_target"] = "yes"
        rec["sources"].add("local-bundle-env")
        if rec["state"] not in {"validated", "packaged"}:
            rec["state"] = "local"
        if item["file"] not in rec["evidence"]:
            rec["evidence"].append(item["file"])

    for key, files in physical.items():
        if key not in merged:
            provider = key[0].split(":", 1)[0]
            merged[key] = {
                "target": key[0], "arch": key[1],
                "family": "upstream-linux" if provider == "upstream" else (provider if provider in {"freebsd", "netbsd", "openbsd", "dragonfly"} else "linux"),
                "state": "packaged", "local_target": "no", "offline_artifact": "no",
                "sources": set(), "evidence": [],
            }
        rec = merged[key]
        rec["offline_artifact"] = "yes"
        rec["sources"].add("physical-bundle-scan")
        if rec["state"] not in {"validated"}:
            rec["state"] = "packaged"
        for filename in files:
            if filename not in rec["evidence"]:
                rec["evidence"].append(filename)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    fields = ["target", "arch", "family", "state", "local_target", "offline_artifact", "sources", "evidence"]
    with args.output.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fields, delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for key in sorted(merged):
            rec = merged[key]
            rec["sources"] = ",".join(sorted(rec["sources"]))
            rec["evidence"] = " | ".join(rec["evidence"])
            writer.writerow(rec)

    counts = Counter(rec["family"] for rec in merged.values())
    print(f"targets={len(merged)} local={sum(x['local_target']=='yes' for x in merged.values())} "
          f"portable={sum(x['offline_artifact']=='yes' for x in merged.values())}")
    print("families=" + ",".join(f"{name}:{counts[name]}" for name in sorted(counts)))


if __name__ == "__main__":
    main()
