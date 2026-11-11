#!/usr/bin/env python3
"""Boot a verified NetBSD evbarm-aarch64 image and prove serial userspace."""
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
            return
        if len(buf) > 2_000_000:
            del buf[:-1_000_000]
    raise TimeoutError(f"timed out waiting for {needle!r}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True, type=Path)
    ap.add_argument("--overlay", required=True, type=Path)
    ap.add_argument("--log", required=True, type=Path)
    ap.add_argument("--qemu", default="qemu-system-aarch64")
    ap.add_argument("--firmware", default="/usr/share/qemu-efi-aarch64/QEMU_EFI.fd")
    ap.add_argument("--timeout", type=int, default=240)
    args = ap.parse_args()
    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.overlay.unlink(missing_ok=True)
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", "-F", "raw",
                    "-b", str(args.image.resolve()), str(args.overlay)], check=True)
    sockpath = str(args.overlay.with_suffix(".serial.sock"))
    try: os.unlink(sockpath)
    except FileNotFoundError: pass
    cmd = [args.qemu, "-machine", "virt", "-cpu", "cortex-a57", "-m", "1024M",
           "-smp", "2", "-bios", args.firmware, "-drive",
           f"if=none,format=qcow2,id=hd0,file={args.overlay}",
           "-device", "virtio-blk-device,drive=hd0", "-nographic",
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
            wait_for(serial, log, b"login: ", args.timeout)
            serial.sendall(b"root\r")
            wait_for(serial, log, b"# ", 30)
            serial.sendall(b"uname -a; /sbin/sysctl -n hw.machine_arch; printf '\\113\\114\\101\\102_NETBSD_ARM64_USERSPACE_OK\\n'\r\n")
            wait_for(serial, log, b"KLAB_NETBSD_ARM64_USERSPACE_OK", 60)
        print("KLAB_NETBSD_ARM64_USERSPACE_OK")
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
