#!/usr/bin/env python3
"""Boot an official NetBSD live image through a disposable QEMU overlay."""
import argparse
import os
from pathlib import Path
import select
import socket
import subprocess
import time


def wait_for(sock, log, needle, timeout):
    end = time.monotonic() + timeout
    buf = bytearray()
    while time.monotonic() < end:
        ready, _, _ = select.select([sock], [], [], min(1, end-time.monotonic()))
        if not ready:
            continue
        chunk = sock.recv(65536)
        if not chunk:
            raise RuntimeError(f"serial channel closed waiting for {needle!r}")
        log.write(chunk); log.flush(); buf.extend(chunk)
        if needle in buf:
            return bytes(buf)
        if len(buf) > 2_000_000:
            del buf[:-1_000_000]
    raise TimeoutError(f"timed out waiting for {needle!r}")


def send(sock, data):
    sock.sendall(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True, type=Path)
    ap.add_argument("--log", required=True, type=Path)
    ap.add_argument("--overlay", required=True, type=Path)
    ap.add_argument("--qemu", default="qemu-system-x86_64")
    ap.add_argument("--timeout", type=int, default=180)
    args = ap.parse_args()
    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.overlay.unlink(missing_ok=True)
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", "-F", "raw", "-b",
                    str(args.image.resolve()), str(args.overlay)], check=True)
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
            wait_for(serial, log, b"SPACE to stop countdown", 30)
            send(serial, b" ")
            wait_for(serial, log, b"Option: [1]:", 10)
            send(serial, b"3\r")
            wait_for(serial, log, b"> ", 10)
            send(serial, b"consdev com0\r")
            wait_for(serial, log, b"> ", 10)
            send(serial, b"boot\r")
            wait_for(serial, log, b"login: ", args.timeout)
            send(serial, b"root\r")
            wait_for(serial, log, b"netbsd# ", 30)
            # Encode the marker with octal escapes so terminal echo cannot
            # satisfy the assertion before the shell executes the command.
            send(serial, b"uname -a; /sbin/sysctl -n hw.machine_arch; printf '\\113\\114\\101\\102_NETBSD_USERSPACE_OK\\n'\r")
            wait_for(serial, log, b"\r\nKLAB_NETBSD_USERSPACE_OK\r\n", 30)
            wait_for(serial, log, b"netbsd# ", 10)
        print("KLAB_NETBSD_USERSPACE_OK")
    finally:
        serial.close()
        proc.terminate()
        try: proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait()
        if proc.stderr:
            err = proc.stderr.read()
            if err and args.log.exists():
                with args.log.open("ab") as log: log.write(b"\nQEMU_STDERR:\n"+err)
        try: os.unlink(sockpath)
        except FileNotFoundError: pass

if __name__ == "__main__":
    main()
