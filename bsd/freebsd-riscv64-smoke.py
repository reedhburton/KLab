#!/usr/bin/env python3
"""Boot FreeBSD riscv64 in KLab's isolated QEMU 10 runtime."""
import argparse
import os
from pathlib import Path
import select
import shlex
import socket
import subprocess
import tempfile
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
        if len(buf) > 3_000_000:
            del buf[:-1_500_000]
    raise TimeoutError(f"timed out waiting for {needles!r}")


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def docker(*args, **kwargs):
    return subprocess.run(["docker", *args], check=True, **kwargs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True, type=Path)
    ap.add_argument("--evidence-dir", required=True, type=Path)
    ap.add_argument("--runtime", default="klab-qemu10-riscv64:local")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--ssh", action="store_true", help="also prove key-authenticated SSH")
    ap.add_argument("--ssh-port", type=int, default=0)
    args = ap.parse_args()
    image = args.image.resolve()
    evidence = args.evidence_dir.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    overlay = evidence / "root-overlay.qcow2"
    logpath = evidence / "smoke.log"
    sockpath = evidence / "serial.sock"
    overlay.unlink(missing_ok=True); sockpath.unlink(missing_ok=True)
    mounts = ["-v", f"{image.parent}:/media:ro", "-v", f"{evidence}:/evidence:rw"]
    docker("run", "--rm", *mounts, args.runtime,
           f"qemu-img create -q -f qcow2 -F qcow2 -b /media/{image.name} /evidence/{overlay.name}")
    name = f"klab-freebsd-riscv64-{os.getpid()}"
    port = args.ssh_port or free_port()
    network = (f"-netdev user,id=klabnet,restrict=on,hostfwd=tcp:127.0.0.1:{port}-10.0.2.15:22 "
               "-device virtio-net-device,netdev=klabnet " if args.ssh else "-net none ")
    qemu = ("exec qemu-system-riscv64 -machine virt -m 1024M -smp 2 "
            "-bios default -kernel /usr/lib/u-boot/qemu-riscv64_smode/uboot.elf "
            f"-drive if=none,format=qcow2,id=hd0,file=/evidence/{overlay.name} "
            "-device virtio-blk-device,drive=hd0 -nographic -monitor none " + network +
            "-no-reboot -serial unix:/evidence/serial.sock,server=on,wait=off")
    docker_network = ["--network", "host"] if args.ssh else []
    keys = tempfile.TemporaryDirectory(prefix="klab-freebsd-riscv64-ssh-") if args.ssh else None
    key = Path(keys.name) / "id_ed25519" if keys else None
    pub = ""
    if key:
        subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)], check=True)
        pub = key.with_suffix(".pub").read_text().strip()
    proc = subprocess.Popen(["docker", "run", "--rm", "--name", name, *docker_network, *mounts,
                             args.runtime, qemu],
                            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    serial = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        end = time.monotonic() + 30
        while True:
            try: serial.connect(str(sockpath)); break
            except OSError:
                if proc.poll() is not None:
                    raise RuntimeError(proc.stderr.read().decode(errors="replace"))
                if time.monotonic() >= end:
                    raise TimeoutError("serial socket did not appear")
                time.sleep(.1)
        with logpath.open("wb") as log:
            wait_any(serial, log, [b"login: "], args.timeout)
            serial.sendall(b"root\r")
            found = wait_any(serial, log, [b"Password:", b"root@freebsd", b"# "], 45)
            if found == b"Password:":
                serial.sendall(b"root\r")
                wait_any(serial, log, [b"# "], 45)
            serial.sendall(b"uname -a; uname -m; printf '\\113\\114\\101\\102_FREEBSD_RISCV64_USERSPACE_OK\\n'\r")
            wait_any(serial, log, [b"\r\nKLAB_FREEBSD_RISCV64_USERSPACE_OK\r\n"], 45)
            if args.ssh:
                quoted = shlex.quote(pub)
                setup = (f"ifconfig vtnet0 inet 10.0.2.15 netmask 255.255.255.0 up; "
                         "route add default 10.0.2.2 >/dev/null 2>&1 || true; "
                         f"mkdir -p /root/.ssh; printf '%s\\n' {quoted} > /root/.ssh/authorized_keys; "
                         "chmod 700 /root /root/.ssh; chmod 600 /root/.ssh/authorized_keys; "
                         "ssh-keygen -A >/dev/null 2>&1; service sshd onestop >/dev/null 2>&1 || true; "
                         "/usr/sbin/sshd -D -e -o PermitRootLogin=yes -o PasswordAuthentication=no "
                         ">/tmp/klab-sshd.log 2>&1 & true; echo KLAB_RISCV64_SSH_SETUP_OK")
                for byte in (setup + "\r").encode():
                    serial.send(bytes((byte,)))
                    time.sleep(.01)
                wait_any(serial, log, [b"\r\nKLAB_RISCV64_SSH_SETUP_OK\r\n"], 90)
                ssh = ["ssh", "-i", str(key), "-p", str(port), "-o", "BatchMode=yes",
                       "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=no",
                       "-o", "UserKnownHostsFile=/dev/null", "-o", "ConnectTimeout=5",
                       "root@127.0.0.1", "uname -s; uname -m; printf KLAB_FREEBSD_RISCV64_SSH_OK"]
                sshlog = evidence / "ssh-client.log"
                for _ in range(30):
                    result = subprocess.run(ssh, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                    sshlog.write_bytes(result.stdout)
                    if result.returncode == 0 and b"KLAB_FREEBSD_RISCV64_SSH_OK" in result.stdout:
                        log.write(b"\nKLAB_FREEBSD_RISCV64_SSH_OK\n")
                        break
                    time.sleep(2)
                else:
                    raise RuntimeError(f"key-authenticated SSH failed; see {sshlog}")
        print("KLAB_FREEBSD_RISCV64_SSH_OK" if args.ssh else "KLAB_FREEBSD_RISCV64_USERSPACE_OK")
    finally:
        serial.close()
        subprocess.run(["docker", "stop", "-t", "5", name],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try: proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            proc.kill(); proc.wait()
        if proc.stderr:
            err = proc.stderr.read()
            if err and logpath.exists():
                with logpath.open("ab") as log:
                    log.write(b"\nQEMU_CONTAINER_STDERR:\n" + err)
        sockpath.unlink(missing_ok=True)
        if keys:
            keys.cleanup()


if __name__ == "__main__":
    main()
