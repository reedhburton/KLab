#!/usr/bin/env python3
"""Fedora Koji metadata helper for KLab.

This helper intentionally separates *discovery/provenance* from package-manager
behavior inside historical Fedora containers.  The Koji build that produced the
kernel is authoritative for the buildroot identity and compiler package builds.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys
import urllib.parse
from typing import Any, Dict, Iterable, List


def die(msg: str) -> None:
    raise SystemExit(f"fedora-koji: ERROR: {msg}")


def canonical_arch(a: str) -> str:
    return {"amd64": "x86_64", "arm64": "aarch64", "i686": "i386"}.get(a, a)


def _row_pkg(row: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "name": str(row.get("name", "")),
        "epoch": row.get("epoch"),
        "version": str(row.get("version", "")),
        "release": str(row.get("release", "")),
        "arch": str(row.get("arch", "")),
    }


def _rpm_lookup(session: Any, row: Dict[str, Any]) -> Dict[str, Any]:
    """Resolve a buildroot-listing row to Koji's canonical RPM record."""
    if row.get("id") is not None:
        info = session.getRPM(int(row["id"]), strict=True)
    else:
        key = {k: row.get(k) for k in ("name", "version", "release", "arch")}
        info = session.getRPM(key, strict=True)
    if not info:
        die(f"Koji RPM lookup failed for {_row_pkg(row)}")
    return info


def select_toolchain_builds(session: Any, listing: Iterable[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Return exact source-build NVRs providing GCC, binutils, and make.

    The binary RPM names are selected from the kernel's own buildroot.  Their
    build IDs are then resolved back to the source builds so download-build can
    retrieve the matching binary subpackages without consulting today's Fedora
    repositories.
    """
    rows = list(listing)
    result: List[Dict[str, Any]] = []
    seen_builds = set()
    for wanted in ("gcc", "binutils", "make"):
        matches = [r for r in rows if r.get("name") == wanted]
        if not matches:
            die(f"kernel Koji buildroot does not contain required toolchain package: {wanted}")
        # Prefer native binary over noarch if there is ever more than one match.
        row = sorted(matches, key=lambda r: (r.get("arch") == "noarch", str(r.get("arch", ""))))[0]
        rpm = _rpm_lookup(session, row)
        bid = rpm.get("build_id")
        if bid is None:
            die(f"Koji RPM {wanted} has no build_id")
        build = session.getBuild(int(bid), strict=True)
        if not build or not build.get("nvr"):
            die(f"Koji build lookup failed for {wanted} build_id={bid}")
        nvr = str(build["nvr"])
        if nvr in seen_builds:
            continue
        seen_builds.add(nvr)
        result.append({
            "seed_package": wanted,
            "rpm": _row_pkg(rpm),
            "rpm_id": rpm.get("id"),
            "build_id": int(bid),
            "build_nvr": nvr,
        })
    return result


def _candidate_buildroot_from_outputs(session: Any, build: Dict[str, Any], arch: str) -> Dict[str, Any] | None:
    rpms = session.listRPMs(buildID=build["id"]) or []
    preferred = []
    for r in rpms:
        if canonical_arch(str(r.get("arch", ""))) != canonical_arch(arch):
            continue
        if r.get("buildroot_id") is None:
            continue
        rank = 0 if r.get("name") == "kernel-core" else 1 if r.get("name") == "kernel" else 2
        preferred.append((rank, int(r["buildroot_id"]), r))
    if not preferred:
        return None
    preferred.sort(key=lambda x: (x[0], x[1]))
    return session.getBuildroot(preferred[0][1], strict=True)


def _candidate_buildroot_from_tasks(session: Any, build: Dict[str, Any], arch: str) -> Dict[str, Any] | None:
    tids = [int(build["task_id"])]
    try:
        desc = session.getTaskDescendents(int(build["task_id"])) or {}
        if isinstance(desc, dict):
            tids.extend(int(x) for x in desc.keys())
        else:
            tids.extend(int(x) for x in desc)
    except Exception:
        pass
    matches = []
    for tid in dict.fromkeys(tids):
        try:
            info = session.getTaskInfo(tid) or {}
        except Exception:
            continue
        if info.get("method") not in ("buildArch", "buildSRPMFromSCM", "build"):
            continue
        try:
            roots = session.listBuildroots(taskID=tid) or []
        except Exception:
            continue
        for br in roots:
            if canonical_arch(str(br.get("arch", ""))) == canonical_arch(arch):
                matches.append(br)
    if not matches:
        return None
    matches.sort(key=lambda b: int(b.get("id", 0)), reverse=True)
    return matches[0]


def capture_manifest(session: Any, nvr: str, arch: str, hub: str) -> Dict[str, Any]:
    build = session.getBuild(nvr, strict=True)
    if not build:
        die(f"Koji build not found: {nvr}")
    br = _candidate_buildroot_from_outputs(session, build, arch)
    if br is None:
        br = _candidate_buildroot_from_tasks(session, build, arch)
    if br is None:
        die(f"could not identify {arch} buildroot for {nvr}")
    br_id = int(br["id"])
    listing = session.getBuildrootListing(br_id) or []
    if not listing:
        die(f"Koji returned an empty buildroot listing for {nvr} buildroot {br_id}")
    packages = sorted((_row_pkg(r) for r in listing), key=lambda x: (x["name"], x["arch"], x["version"], x["release"]))
    toolchain = select_toolchain_builds(session, listing)
    repo_info = None
    try:
        if br.get("repo_id") is not None:
            repo_info = session.repoInfo(int(br["repo_id"]), strict=True)
    except Exception:
        repo_info = None
    build_cfg = None
    try:
        event = ((repo_info or {}).get("create_event") or br.get("repo_create_event_id") or br.get("create_event_id"))
        build_cfg = session.getBuildConfig(br.get("tag_id") or br.get("tag_name"), event=event)
    except Exception:
        build_cfg = None
    external_repos = None
    try:
        event = ((repo_info or {}).get("create_event") or br.get("repo_create_event_id") or br.get("create_event_id"))
        external_repos = session.getExternalRepoList(br.get("tag_id") or br.get("tag_name"), event=event)
    except Exception:
        external_repos = None
    manifest: Dict[str, Any] = {
        "schema": "klab-fedora-koji-buildroot-v1",
        "hub": hub,
        "kernel_build": {
            "id": build.get("id"), "nvr": build.get("nvr"), "task_id": build.get("task_id"),
            "creation_event_id": build.get("creation_event_id"),
        },
        "arch": canonical_arch(arch),
        "buildroot": {
            k: br.get(k) for k in (
                "id", "arch", "tag_id", "tag_name", "repo_id", "repo_create_event_id",
                "create_event_id", "task_id", "host_name", "container_type"
            )
        },
        "repo_info": repo_info,
        "build_config": build_cfg,
        "external_repos": external_repos,
        "toolchain_builds": toolchain,
        "packages": packages,
    }
    canonical = json.dumps(packages, sort_keys=True, separators=(",", ":")).encode()
    manifest["package_inventory_sha256"] = hashlib.sha256(canonical).hexdigest()
    return manifest




def resolve_fallback_plan(session: Any, m: Dict[str, Any]) -> Dict[str, Any]:
    """Map the recorded buildroot inventory back to exact retained Koji RPMs.

    This is intentionally lazy: normal capture records the compact NEVRA
    inventory.  We only perform the larger RPM/build lookup when the original
    Koji tag/repo_id repository has expired and KLab must reconstruct it from
    retained package builds.
    """
    target_arch = canonical_arch(str(m.get("arch") or ""))
    if not target_arch:
        die("manifest has no architecture")
    rows = []
    builds: Dict[str, Dict[str, Any]] = {}
    for row in (m.get("packages") or []):
        raw_arch = str(row.get("arch") or "")
        # Fedora kernel buildroots used by KLab are currently native x86_64,
        # but preserve noarch packages too.  Ignore foreign multilib payloads;
        # they are not required for the external-module build environment.
        if canonical_arch(raw_arch) != target_arch and raw_arch != "noarch":
            continue
        rpm = _rpm_lookup(session, row)
        bid = rpm.get("build_id")
        if bid is None:
            die(f"Koji RPM has no build_id: {_row_pkg(row)}")
        b = session.getBuild(int(bid), strict=True)
        if not b or not b.get("nvr"):
            die(f"Koji build lookup failed for build_id={bid}")
        build_nvr = str(b["nvr"])
        builds.setdefault(build_nvr, {"build_id": int(bid), "build_nvr": build_nvr})
        name = str(rpm.get("name") or row.get("name") or "")
        version = str(rpm.get("version") or row.get("version") or "")
        release = str(rpm.get("release") or row.get("release") or "")
        arch = str(rpm.get("arch") or row.get("arch") or "")
        if not all((name, version, release, arch)):
            die(f"incomplete Koji RPM identity for {_row_pkg(row)}")
        rows.append({
            "name": name,
            "epoch": rpm.get("epoch", row.get("epoch")),
            "version": version,
            "release": release,
            "arch": arch,
            "rpm_id": rpm.get("id"),
            "build_id": int(bid),
            "build_nvr": build_nvr,
            "filename": f"{name}-{version}-{release}.{arch}.rpm",
        })
    if not rows:
        die("no native/noarch RPMs resolved from Koji buildroot inventory")
    rows.sort(key=lambda x: (x["name"], x["arch"], x["version"], x["release"]))
    inv = str(m.get("package_inventory_sha256") or "")
    return {
        "schema": "klab-fedora-koji-fallback-plan-v1",
        "kernel_build": m.get("kernel_build"),
        "arch": target_arch,
        "buildroot": m.get("buildroot"),
        "package_inventory_sha256": inv,
        "builds": sorted(builds.values(), key=lambda x: x["build_nvr"]),
        "packages": rows,
    }


def load_fallback_plan(path: str) -> Dict[str, Any]:
    try:
        p = json.loads(pathlib.Path(path).read_text())
    except Exception as e:
        die(f"cannot read fallback plan {path}: {e}")
    if p.get("schema") != "klab-fedora-koji-fallback-plan-v1":
        die("invalid Fedora Koji fallback-plan schema")
    return p


def cmd_fallback_plan(a: argparse.Namespace) -> None:
    try:
        import koji  # type: ignore
    except Exception as e:
        die(f"python3-koji is required: {e}")
    m = load_manifest(a.manifest)
    session = koji.ClientSession(a.hub)
    plan = resolve_fallback_plan(session, m)
    out = pathlib.Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
    print(f"{len(plan['packages'])}\t{len(plan['builds'])}\t{out}")


def cmd_fallback_builds(a: argparse.Namespace) -> None:
    p = load_fallback_plan(a.plan)
    for row in p.get("builds") or []:
        nvr = row.get("build_nvr")
        if nvr:
            print(nvr)


def cmd_fallback_expected(a: argparse.Namespace) -> None:
    p = load_fallback_plan(a.plan)
    for row in p.get("packages") or []:
        fn = row.get("filename")
        if fn:
            print(fn)


def cmd_fallback_verify_dir(a: argparse.Namespace) -> None:
    p = load_fallback_plan(a.plan)
    root = pathlib.Path(a.directory)
    expected = {str(x.get("filename")) for x in (p.get("packages") or []) if x.get("filename")}
    actual = {x.name for x in root.glob("*.rpm")}
    extra = actual - expected
    for name in sorted(extra):
        (root / name).unlink()
    actual = {x.name for x in root.glob("*.rpm")}
    missing = sorted(expected - actual)
    if missing:
        sample = ", ".join(missing[:8])
        die(f"Koji fallback repository is missing {len(missing)} recorded buildroot RPM(s): {sample}")
    print(f"{len(expected)}\t{root}")


def compiler_metadata_from_manifest(m: Dict[str, Any]) -> Dict[str, str]:
    rows = {str(x.get("seed_package")): x for x in (m.get("toolchain_builds") or [])}
    for name in ("gcc", "binutils"):
        if name not in rows:
            die(f"manifest contains no {name} toolchain build")
    gcc_rpm = rows["gcc"].get("rpm") or {}
    bin_rpm = rows["binutils"].get("rpm") or {}
    cc_version = str(gcc_rpm.get("version") or "").strip()
    bin_version = str(bin_rpm.get("version") or "").strip()
    if not cc_version or not bin_version:
        die("toolchain build metadata is missing package versions")
    arch = canonical_arch(str(m.get("arch") or ""))
    targets = {
        "x86_64": "x86_64-redhat-linux",
        "i386": "i686-redhat-linux",
        "aarch64": "aarch64-redhat-linux",
        "armv7": "armv7hl-redhat-linux-gnueabi",
    }
    target = targets.get(arch)
    if not target:
        die(f"no Fedora GCC target mapping for architecture: {arch}")
    return {
        "cc_path": "/usr/bin/gcc",
        "cc_version": cc_version,
        "cc_target": target,
        "as_path": "/usr/bin/as",
        "as_version": bin_version,
        "ld_path": "/usr/bin/ld",
        "ld_version": bin_version,
    }

def load_manifest(path: str) -> Dict[str, Any]:
    try:
        m = json.loads(pathlib.Path(path).read_text())
    except Exception as e:
        die(f"cannot read manifest {path}: {e}")
    if m.get("schema") != "klab-fedora-koji-buildroot-v1":
        die("invalid Fedora Koji buildroot manifest schema")
    return m


def cmd_capture(a: argparse.Namespace) -> None:
    try:
        import koji  # type: ignore
    except Exception as e:
        die(f"python3-koji is required: {e}")
    session = koji.ClientSession(a.hub)
    m = capture_manifest(session, a.nvr, a.arch, a.hub)
    out = pathlib.Path(a.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(m, indent=2, sort_keys=True) + "\n")
    print(f"{m['buildroot']['id']}\t{out}")


def cmd_toolchain_builds(a: argparse.Namespace) -> None:
    m = load_manifest(a.manifest)
    rows = m.get("toolchain_builds") or []
    if not rows:
        die("manifest contains no toolchain builds")
    for row in rows:
        nvr = row.get("build_nvr")
        if not nvr:
            die("toolchain build row missing build_nvr")
        print(nvr)



def cmd_compiler_json(a: argparse.Namespace) -> None:
    m = load_manifest(a.manifest)
    print(json.dumps(compiler_metadata_from_manifest(m), sort_keys=True))


def koji_repo_url(m: Dict[str, Any], topurl: str) -> str:
    br = m.get("buildroot") or {}
    tag = str(br.get("tag_name") or (m.get("repo_info") or {}).get("tag_name") or "").strip()
    repo_id = br.get("repo_id") or (m.get("repo_info") or {}).get("id")
    arch = canonical_arch(str(m.get("arch") or "").strip())
    if not tag or repo_id is None or not arch:
        die("manifest lacks tag/repo/arch needed to construct Koji buildroot repository URL")
    return "%s/repos/%s/%s/%s/" % (
        topurl.rstrip("/"), urllib.parse.quote(tag, safe=""), int(repo_id), urllib.parse.quote(arch, safe="")
    )


def cmd_repo_url(a: argparse.Namespace) -> None:
    print(koji_repo_url(load_manifest(a.manifest), a.topurl))

def cmd_summary(a: argparse.Namespace) -> None:
    m = load_manifest(a.manifest)
    print(json.dumps({
        "kernel": m.get("kernel_build", {}).get("nvr"),
        "arch": m.get("arch"),
        "buildroot_id": m.get("buildroot", {}).get("id"),
        "tag": m.get("buildroot", {}).get("tag_name"),
        "repo_id": m.get("buildroot", {}).get("repo_id"),
        "repo_state": (m.get("repo_info") or {}).get("state"),
        "package_count": len(m.get("packages") or []),
        "toolchain_builds": [x.get("build_nvr") for x in m.get("toolchain_builds") or []],
        "package_inventory_sha256": m.get("package_inventory_sha256"),
    }, sort_keys=True))


def main() -> None:
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("capture")
    p.add_argument("--hub", default="https://koji.fedoraproject.org/kojihub")
    p.add_argument("--nvr", required=True)
    p.add_argument("--arch", required=True)
    p.add_argument("--output", required=True)
    p.set_defaults(func=cmd_capture)
    p = sp.add_parser("toolchain-builds")
    p.add_argument("manifest")
    p.set_defaults(func=cmd_toolchain_builds)
    p = sp.add_parser("compiler-json")
    p.add_argument("manifest")
    p.set_defaults(func=cmd_compiler_json)
    p = sp.add_parser("repo-url")
    p.add_argument("manifest")
    p.add_argument("--topurl", required=True)
    p.set_defaults(func=cmd_repo_url)
    p = sp.add_parser("fallback-plan")
    p.add_argument("manifest")
    p.add_argument("--hub", default="https://koji.fedoraproject.org/kojihub")
    p.add_argument("--output", required=True)
    p.set_defaults(func=cmd_fallback_plan)
    p = sp.add_parser("fallback-builds")
    p.add_argument("plan")
    p.set_defaults(func=cmd_fallback_builds)
    p = sp.add_parser("fallback-expected")
    p.add_argument("plan")
    p.set_defaults(func=cmd_fallback_expected)
    p = sp.add_parser("fallback-verify-dir")
    p.add_argument("plan")
    p.add_argument("directory")
    p.set_defaults(func=cmd_fallback_verify_dir)
    p = sp.add_parser("summary")
    p.add_argument("manifest")
    p.set_defaults(func=cmd_summary)
    a = ap.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
