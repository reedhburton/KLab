#!/usr/bin/env python3
"""Boot an official FreeBSD i386 VM image and prove serial userspace."""
import argparse
import os
from pathlib import Path
import select
import socket
import subprocess
import time


def wait_any(sock, log, needles, timeout):
    end = time.monotonic() + timeout
    buf = bytearray()
    while time.monotonic() < end:
        ready, _, _ = select.select([sock], [], [], min(1, end-time.monotonic()))
        if not ready:
            continue
        chunk = sock.recv(65536)
        if not chunk:
            raise RuntimeError(f"serial closed waiting for {needles!r}")
        log.write(chunk); log.flush(); buf.extend(chunk)
        for needle in needles:
            if needle in buf:
                return needle
        if len(buf) > 2_000_000:
            del buf[:-1_000_000]
    raise TimeoutError(f"timed out waiting for {needles!r}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True, type=Path)
    ap.add_argument("--overlay", required=True, type=Path)
    ap.add_argument("--log", required=True, type=Path)
    ap.add_argument("--qemu", default="qemu-system-i386")
    ap.add_argument("--timeout", type=int, default=240)
    args = ap.parse_args()
    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.overlay.unlink(missing_ok=True)
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", "-F", "qcow2",
                    "-b", str(args.image.resolve()), str(args.overlay)], check=True)
    sockpath = str(args.overlay.with_suffix(".serial.sock"))
    try: os.unlink(sockpath)
    except FileNotFoundError: pass
    cmd = [args.qemu, "-enable-kvm", "-cpu", "host", "-machine", "pc",
           "-m", "1024M", "-smp", "2", "-drive",
           f"file={args.overlay},format=qcow2,if=virtio", "-nographic",
           "-serial", f"unix:{sockpath},server=on,wait=off", "-monitor", "none",
           "-net", "none", "-no-reboot"]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    serial = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        end = time.monotonic() + 15
        while True:
            try: serial.connect(sockpath); break
            except OSError:
                if time.monotonic() >= end: raise
                time.sleep(.05)
        with args.log.open("wb") as log:
            wait_any(serial, log, [b"Autoboot in"], 60)
            serial.sendall(b" ")
            serial.sendall(b"5")
            wait_any(serial, log, [b"Serial primary"], 20)
            serial.sendall(b"\r")
            wait_any(serial, log, [b"login: "], args.timeout)
            serial.sendall(b"root\r")
            found = wait_any(serial, log, [b"Password:", b"root@freebsd", b"# "], 30)
            if found == b"Password:":
                serial.sendall(b"root\r")
                wait_any(serial, log, [b"# "], 30)
            serial.sendall(b"uname -a; uname -m; printf '\\113\\114\\101\\102_FREEBSD_I386_USERSPACE_OK\\n'\r")
            wait_any(serial, log, [b"\r\nKLAB_FREEBSD_I386_USERSPACE_OK\r\n"], 30)
        print("KLAB_FREEBSD_I386_USERSPACE_OK")
    finally:
        serial.close()
        proc.terminate()
        try: proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait()
        if proc.stderr:
            err = proc.stderr.read()
            if err and args.log.exists():
                with args.log.open("ab") as log:
                    log.write(b"\nQEMU_STDERR:\n" + err)
        try: os.unlink(sockpath)
        except FileNotFoundError: pass


if __name__ == "__main__":
    main()
