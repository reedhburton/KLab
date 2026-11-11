#!/usr/bin/env python3
"""Boot an official OpenBSD installer ISO and prove serial shell userspace."""
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
        ready, _, _ = select.select([sock], [], [], min(1, end - time.monotonic()))
        if not ready:
            continue
        chunk = sock.recv(65536)
        if not chunk:
            raise RuntimeError(f"serial closed waiting for {needle!r}")
        log.write(chunk)
        log.flush()
        buf.extend(chunk)
        if needle in buf:
            return
        if len(buf) > 2_000_000:
            del buf[:-1_000_000]
    raise TimeoutError(f"timed out waiting for {needle!r}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iso", required=True, type=Path)
    ap.add_argument("--log", required=True, type=Path)
    ap.add_argument("--qemu", default="qemu-system-x86_64")
    ap.add_argument("--timeout", type=int, default=240)
    args = ap.parse_args()
    args.log.parent.mkdir(parents=True, exist_ok=True)
    sockpath = str(args.log.with_suffix(".serial.sock"))
    try:
        os.unlink(sockpath)
    except FileNotFoundError:
        pass
    cmd = [
        args.qemu, "-enable-kvm", "-cpu", "host", "-machine", "pc",
        "-m", "1024M", "-smp", "2", "-cdrom", str(args.iso.resolve()),
        "-boot", "d", "-nographic", "-serial",
        f"unix:{sockpath},server=on,wait=off", "-monitor", "none", "-net",
        "none", "-no-reboot",
    ]
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    serial = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        end = time.monotonic() + 15
        while True:
            try:
                serial.connect(sockpath)
                break
            except OSError:
                if time.monotonic() >= end:
                    raise
                time.sleep(0.05)
        with args.log.open("wb") as log:
            wait_for(serial, log, b"boot>", 45)
            serial.sendall(b"set tty com0\r")
            wait_for(serial, log, b"boot>", 10)
            serial.sendall(b"boot\r")
            wait_for(serial, log, b"(I)nstall, (U)pgrade, (A)utoinstall or (S)hell?", args.timeout)
            serial.sendall(b"S\r")
            wait_for(serial, log, b"# ", 30)
            # Octal escapes ensure terminal echo cannot satisfy the assertion.
            serial.sendall(
                b"/sbin/sysctl kern.version hw.machine; x=KLAB_; echo ${x}OPENBSD_INSTALLER_USERSPACE_OK\r"
            )
            wait_for(serial, log, b"\r\nKLAB_OPENBSD_INSTALLER_USERSPACE_OK\r\n", 30)
            wait_for(serial, log, b"# ", 10)
        print("KLAB_OPENBSD_INSTALLER_USERSPACE_OK")
    finally:
        serial.close()
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        err = proc.stderr.read() if proc.stderr else b""
        if err and args.log.exists():
            with args.log.open("ab") as log:
                log.write(b"\nQEMU_STDERR:\n" + err)
        try:
            os.unlink(sockpath)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    main()
