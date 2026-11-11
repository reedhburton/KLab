#!/usr/bin/env python3
"""KLab local dashboard and portable-artifact repository server."""
from __future__ import annotations

import argparse
import hashlib
import hmac
import html
import json
import mimetypes
import os
from pathlib import Path
import re
import shlex
import ssl
import subprocess
import sys
import tempfile
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import quote, unquote, urlsplit

ARTIFACT_SUFFIXES = (
    ".klab", ".klabbuildenv", ".klabdistrotoolchain", ".klabtoolchain",
    ".klabrootfs", ".klabsdk", ".klabfirmware", ".klabsource",
)
MAX_UPLOAD = 1024 ** 4  # 1 TiB safety ceiling; real limit remains available disk.


def read_env(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    try:
        for raw in path.read_text(errors="replace").splitlines():
            if "=" not in raw or raw.lstrip().startswith("#"):
                continue
            key, value = raw.split("=", 1)
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
                continue
            try:
                words = shlex.split(value)
                result[key] = words[0] if words else ""
            except ValueError:
                result[key] = value.strip("'\"")
    except OSError:
        pass
    return result


def targets(root: Path) -> list[dict]:
    rows = []
    base = root / "targets" / "kernels"
    for env in sorted(base.glob("*/*/*/*/bundle.env")):
        rel = env.relative_to(base).parts
        if len(rel) != 5:
            continue
        provider, release, arch_dir, kernel_dir, _ = rel
        data = read_env(env)
        kernel = data.get("BUNDLE_KERNEL_RELEASE", kernel_dir)
        if kernel_dir != kernel:  # skip retained backup directories
            continue
        arch = data.get("BUNDLE_ARCH", arch_dir)
        backend = data.get("BUNDLE_BACKEND", "freebsd" if provider == "freebsd" else "linux")
        target = data.get("BUNDLE_TARGET_ID", f"{provider}:{release}:{kernel}")
        rows.append({
            "target": target, "provider": provider, "release": release,
            "kernel": kernel, "arch": arch, "backend": backend,
            "userspace": data.get("BUNDLE_GUEST_USERSPACE_SPEC", "unbound"),
            "toolchain": data.get("BUNDLE_DISTRO_TOOLCHAIN_ID",
                                  data.get("BUNDLE_TOOLCHAIN_ID", "none")),
        })
    return rows


def process_alive(pid: str) -> bool:
    try:
        os.kill(int(pid), 0)
        return True
    except (ValueError, ProcessLookupError, PermissionError, OSError):
        return False


def jobs(root: Path) -> dict:
    sessions = []
    session_root = root / "work" / "sessions"
    if session_root.is_dir():
        for directory in sorted(session_root.iterdir()):
            if not directory.is_dir():
                continue
            data = read_env(directory / "session.env")
            pid = ""
            try:
                pid = (directory / "pid").read_text().strip()
            except OSError:
                pass
            sessions.append({
                "name": directory.name,
                "state": "running" if process_alive(pid) else "stopped",
                "pid": pid or None,
                "target": data.get("SESSION_TARGET", "?"),
                "arch": data.get("SESSION_ARCH", "?"),
                "backend": data.get("SESSION_BACKEND", "?"),
                "userspace": data.get("SESSION_USERSPACE", "?"),
            })

    queues = []
    results = root / "results"
    if results.is_dir():
        status_files = sorted(
            results.rglob("status.tsv"),
            key=lambda p: p.stat().st_mtime if p.exists() else 0,
            reverse=True,
        )[:100]
        for status in status_files:
            counts: dict[str, int] = {}
            try:
                lines = status.read_text(errors="replace").splitlines()
                for line in lines[1:]:
                    fields = line.split("\t")
                    value = next((x for x in fields if x in ("PASS", "FAIL", "RUNNING", "PENDING", "SKIP")), None)
                    if value:
                        counts[value] = counts.get(value, 0) + 1
                queues.append({
                    "path": str(status.relative_to(root)),
                    "updated": int(status.stat().st_mtime),
                    "rows": max(0, len(lines) - 1),
                    "counts": counts,
                })
            except OSError:
                continue
    return {"sessions": sessions, "queues": queues}


def artifact_index(repo: Path) -> list[dict]:
    indexed: dict[str, dict] = {}
    index = repo / "INDEX.tsv"
    if index.is_file():
        try:
            lines = index.read_text(errors="replace").splitlines()
            header = lines[0].split("\t") if lines else []
            for line in lines[1:]:
                fields = line.split("\t")
                if len(fields) != len(header):
                    continue
                row = dict(zip(header, fields))
                filename = row.get("file", "")
                if filename:
                    indexed[filename] = row
        except OSError:
            pass

    rows = []
    if not repo.is_dir():
        return rows
    for path in sorted(repo.rglob("*")):
        if not path.is_file() or not path.name.endswith(ARTIFACT_SUFFIXES):
            continue
        rel = str(path.relative_to(repo))
        meta = indexed.get(rel, indexed.get(path.name, {}))
        stat = path.stat()
        rows.append({
            "file": rel,
            "bytes": stat.st_size,
            "modified": int(stat.st_mtime),
            "target": meta.get("target"),
            "arch": meta.get("architecture"),
            "sha256": meta.get("sha256"),
            "url": "/repo/" + quote(rel, safe="/"),
        })
    return rows


def page(summary: dict) -> bytes:
    data = json.dumps(summary).replace("</", "<\\/")
    title = "KLab dashboard"
    body = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>
:root{{--bg:#0b1020;--panel:#151d33;--line:#2b3858;--text:#e8edf8;--muted:#9aabc8;--good:#64d98b;--bad:#ff7b7b;--accent:#72a7ff}}
*{{box-sizing:border-box}} body{{margin:0;background:var(--bg);color:var(--text);font:14px system-ui,sans-serif}}
header{{padding:24px 5vw;border-bottom:1px solid var(--line);background:#10172a}} h1{{margin:0 0 5px;font-size:26px}}
main{{padding:24px 5vw;display:grid;gap:20px}} .cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px}}
.card,section{{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px}} .big{{font-size:28px;font-weight:700}}
.muted{{color:var(--muted)}} table{{width:100%;border-collapse:collapse}} th,td{{text-align:left;padding:8px;border-bottom:1px solid var(--line)}}
th{{color:var(--muted);position:sticky;top:0;background:var(--panel)}} .scroll{{overflow:auto;max-height:430px}}
a{{color:var(--accent)}} .PASS,.running{{color:var(--good)}} .FAIL{{color:var(--bad)}} code{{color:#bdd1ff}}
input{{width:100%;padding:9px;background:#0c1326;color:var(--text);border:1px solid var(--line);border-radius:6px;margin-bottom:8px}}
</style></head>
<body><header><h1>KLab</h1><div class="muted">Targets, sessions, queues, and portable artifacts</div></header>
<main><div class="cards" id="cards"></div>
<section><h2>Running sessions</h2><div class="scroll"><table id="sessions"></table></div></section>
<section><h2>Recent jobs</h2><div class="scroll"><table id="jobs"></table></div></section>
<section><h2>Available targets</h2><input id="target-filter" placeholder="Filter targets"><div class="scroll"><table id="targets"></table></div></section>
<section><h2>Artifact repository</h2><input id="artifact-filter" placeholder="Filter artifacts"><div class="scroll"><table id="artifacts"></table></div></section>
</main><script>
const D={data};
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[c]));
const size=n=>{{for(const u of ['B','KiB','MiB','GiB','TiB']){{if(n<1024)return n.toFixed(n<10&&u!='B'?1:0)+' '+u;n/=1024}}return n.toFixed(1)+' PiB'}};
function table(id,heads,rows){{document.getElementById(id).innerHTML='<thead><tr>'+heads.map(x=>'<th>'+esc(x[0])+'</th>').join('')+'</tr></thead><tbody>'+rows.map(r=>'<tr>'+heads.map(x=>'<td>'+x[1](r)+'</td>').join('')+'</tr>').join('')+'</tbody>'}}
document.getElementById('cards').innerHTML=[
 ['Targets',D.targets.length],['Running',D.jobs.sessions.filter(x=>x.state==='running').length],
 ['Recent queues',D.jobs.queues.length],['Artifacts',D.artifacts.length],
 ['Repository',size(D.artifacts.reduce((n,x)=>n+x.bytes,0))]
].map(x=>'<div class="card"><div class="muted">'+x[0]+'</div><div class="big">'+x[1]+'</div></div>').join('');
table('sessions',[['Name',r=>esc(r.name)],['State',r=>'<span class="'+esc(r.state)+'">'+esc(r.state)+'</span>'],['Target',r=>'<code>'+esc(r.target)+'</code>'],['Arch',r=>esc(r.arch)],['Userspace',r=>esc(r.userspace)]],D.jobs.sessions);
table('jobs',[['Status file',r=>'<code>'+esc(r.path)+'</code>'],['Updated',r=>new Date(r.updated*1000).toLocaleString()],['Rows',r=>r.rows],['Results',r=>Object.entries(r.counts).map(x=>'<span class="'+esc(x[0])+'">'+esc(x[0])+': '+x[1]+'</span>').join(' &nbsp; ')]],D.jobs.queues);
const targetHeads=[['Target',r=>'<code>'+esc(r.target)+'</code>'],['Arch',r=>esc(r.arch)],['Backend',r=>esc(r.backend)],['Userspace',r=>esc(r.userspace)]];
const artifactHeads=[['File',r=>'<a href="'+esc(r.url)+'">'+esc(r.file)+'</a>'],['Size',r=>size(r.bytes)],['Target',r=>esc(r.target||'')],['Arch',r=>esc(r.arch||'')],['SHA-256',r=>'<code>'+esc((r.sha256||'').slice(0,16))+'</code>']];
const drawTargets=()=>table('targets',targetHeads,D.targets.filter(r=>JSON.stringify(r).toLowerCase().includes(document.getElementById('target-filter').value.toLowerCase())));
const drawArtifacts=()=>table('artifacts',artifactHeads,D.artifacts.filter(r=>JSON.stringify(r).toLowerCase().includes(document.getElementById('artifact-filter').value.toLowerCase())));
document.getElementById('target-filter').oninput=drawTargets;document.getElementById('artifact-filter').oninput=drawArtifacts;drawTargets();drawArtifacts();
</script></body></html>"""
    return body.encode()


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, handler, root: Path, repo: Path, token: str | None):
        super().__init__(address, handler)
        self.root, self.repo, self.token = root, repo, token

    def snapshot(self):
        ts = targets(self.root)
        js = jobs(self.root)
        arts = artifact_index(self.repo)
        return {"generated_at": int(time.time()), "root": str(self.root),
                "repo": str(self.repo), "targets": ts, "jobs": js, "artifacts": arts}


class Handler(BaseHTTPRequestHandler):
    server_version = "KLabRepo/1"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("klab-serve: " + fmt % args + "\n")

    def send_headers(self, status=200, content_type="application/json", length=None, extra=None):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'")
        if length is not None:
            self.send_header("Content-Length", str(length))
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()

    def json(self, value, status=200):
        payload = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()
        self.send_headers(status, length=len(payload))
        self.wfile.write(payload)

    def safe_repo_path(self, encoded: str) -> Path | None:
        try:
            rel = unquote(encoded).lstrip("/")
            candidate = (self.server.repo / rel).resolve()
            candidate.relative_to(self.server.repo.resolve())
            return candidate
        except (ValueError, OSError):
            return None

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/healthz":
            payload = b"ok\n"; self.send_headers(200, "text/plain", len(payload)); self.wfile.write(payload)
        elif path in ("/", "/index.html"):
            payload = page(self.server.snapshot()); self.send_headers(200, "text/html; charset=utf-8", len(payload)); self.wfile.write(payload)
        elif path == "/api/status":
            self.json(self.server.snapshot())
        elif path == "/api/targets":
            self.json(targets(self.server.root))
        elif path == "/api/jobs":
            self.json(jobs(self.server.root))
        elif path == "/api/artifacts":
            self.json(artifact_index(self.server.repo))
        elif path.startswith("/repo/"):
            self.send_artifact(path[len("/repo/"):])
        else:
            self.json({"error": "not found"}, 404)

    def do_HEAD(self):
        path = urlsplit(self.path).path
        if path.startswith("/repo/"):
            self.send_artifact(path[len("/repo/"):], head=True)
        else:
            self.json({"error": "not found"}, 404)

    def send_artifact(self, encoded: str, head=False):
        file = self.safe_repo_path(encoded)
        if file is None or not file.is_file() or not file.name.endswith(ARTIFACT_SUFFIXES):
            self.json({"error": "artifact not found"}, 404); return
        size = file.stat().st_size
        start, end, status = 0, size - 1, 200
        range_header = self.headers_in("Range")
        if range_header:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", range_header.strip())
            if not match:
                self.send_headers(416, length=0, extra={"Content-Range": f"bytes */{size}"}); return
            first, last = match.groups()
            if first:
                start = int(first); end = int(last) if last else size - 1
            elif last:
                start = max(0, size - int(last))
            if start >= size or end < start:
                self.send_headers(416, length=0, extra={"Content-Range": f"bytes */{size}"}); return
            end = min(end, size - 1); status = 206
        length = max(0, end - start + 1)
        extra = {"Accept-Ranges": "bytes", "Content-Disposition": f'attachment; filename="{file.name}"'}
        if status == 206:
            extra["Content-Range"] = f"bytes {start}-{end}/{size}"
        content_type = mimetypes.guess_type(file.name)[0] or "application/octet-stream"
        self.send_headers(status, content_type, length, extra)
        if head:
            return
        with file.open("rb") as stream:
            stream.seek(start); remaining = length
            while remaining:
                chunk = stream.read(min(1024 * 1024, remaining))
                if not chunk: break
                self.wfile.write(chunk); remaining -= len(chunk)

    def headers_in(self, name):
        return self.headers.get(name)

    def do_PUT(self):
        path = urlsplit(self.path).path
        if not path.startswith("/api/artifacts/"):
            self.json({"error": "not found"}, 404); return
        if not self.server.token:
            self.json({"error": "uploads disabled"}, 405); return
        supplied = self.headers.get("Authorization", "")
        expected = "Bearer " + self.server.token
        if not hmac.compare_digest(supplied, expected):
            self.json({"error": "unauthorized"}, 401); return
        destination = self.safe_repo_path(path[len("/api/artifacts/"):])
        if destination is None or not destination.name.endswith(ARTIFACT_SUFFIXES):
            self.json({"error": "invalid artifact path"}, 400); return
        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            self.json({"error": "Content-Length required"}, 411); return
        if length < 0 or length > MAX_UPLOAD:
            self.json({"error": "invalid upload length"}, 413); return
        destination.parent.mkdir(parents=True, exist_ok=True)
        fd, temp_name = tempfile.mkstemp(prefix="." + destination.name + ".", suffix=".part", dir=destination.parent)
        digest = hashlib.sha256(); remaining = length
        try:
            with os.fdopen(fd, "wb") as output:
                while remaining:
                    chunk = self.rfile.read(min(1024 * 1024, remaining))
                    if not chunk: raise OSError("upload ended early")
                    output.write(chunk); digest.update(chunk); remaining -= len(chunk)
                output.flush(); os.fsync(output.fileno())
            wanted = self.headers.get("X-KLab-SHA256", "").lower()
            actual = digest.hexdigest()
            if wanted and not hmac.compare_digest(wanted, actual):
                os.unlink(temp_name); self.json({"error": "checksum mismatch", "sha256": actual}, 422); return
            os.replace(temp_name, destination)
            self.json({"file": str(destination.relative_to(self.server.repo)),
                       "bytes": length, "sha256": actual}, 201)
        except (OSError, ConnectionError) as exc:
            try: os.unlink(temp_name)
            except OSError: pass
            self.json({"error": str(exc)}, 400)


def main():
    parser = argparse.ArgumentParser(description="KLab dashboard and artifact repository")
    parser.add_argument("--root", default=os.environ.get("KLAB_ROOT", str(Path.home() / "klab")))
    parser.add_argument("--repo", default=os.environ.get("KLAB_REPO", str(Path.home() / "klab-offline")))
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--upload-token-file")
    parser.add_argument("--tls-cert")
    parser.add_argument("--tls-key")
    parser.add_argument("--port-file", help=argparse.SUPPRESS)
    args = parser.parse_args()
    root, repo = Path(args.root).expanduser().resolve(), Path(args.repo).expanduser().resolve()
    repo.mkdir(parents=True, exist_ok=True)
    token = None
    if args.upload_token_file:
        token_path = Path(args.upload_token_file).expanduser()
        token = token_path.read_text().strip()
        if not token: parser.error("upload token file is empty")
    if bool(args.tls_cert) != bool(args.tls_key):
        parser.error("--tls-cert and --tls-key must be used together")
    server = Server((args.bind, args.port), Handler, root, repo, token)
    if args.tls_cert:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(args.tls_cert, args.tls_key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
    port = server.server_address[1]
    if args.port_file:
        Path(args.port_file).write_text(str(port) + "\n")
    scheme = "https" if args.tls_cert else "http"
    mode = "authenticated uploads" if token else "read-only"
    print(f"KLab dashboard: {scheme}://{args.bind}:{port} ({mode})", flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: server.server_close()


if __name__ == "__main__":
    main()
