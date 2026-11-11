# BSD v1 validation floor

KLab's required BSD 1.0 floor passes as of 2026-10-07.

| Target | Architecture | Required result | Verified result |
| --- | --- | --- | --- |
| FreeBSD 15.1-RELEASE | amd64 | kernel module | MODULE_PASS |
| FreeBSD 15.1-RELEASE | arm64 | kernel module | MODULE_PASS |
| FreeBSD 14.5-RELEASE | amd64 | kernel module | MODULE_PASS |
| NetBSD 11.0 | amd64 | userspace | USERSPACE_PASS |
| NetBSD 11.0 | i386 | userspace | USERSPACE_PASS |
| OpenBSD 7.9 | amd64 | userspace | USERSPACE_PASS |
| OpenBSD 7.9 | arm64 | userspace | USERSPACE_PASS |
| DragonFly BSD 6.4.2 | x86_64 | userspace | USERSPACE_PASS |

Run the machine-readable gate with:

```sh
python3 tools/bsd-v1-status.py --check
```

The command exits successfully only when every target in
`bsd/targets-v1.json` under `policy.minimum_required` reaches its required
level.

## FreeBSD arm64 runtime

FreeBSD 15.1 arm64 needs a current QEMU. The host's QEMU 6.2 panics during
PSCI startup, while QEMU 10.0.13 boots the same verified media and completes
the module workflow. Build the isolated runtime with:

```sh
docker build -f containers/qemu10-aarch64.Dockerfile \
  -t klab-qemu10-aarch64:local .
```

KLab carries a VirtIO console transport for this guest. FreeBSD exposes the
agent endpoint as `/dev/ttyV0.1`; `bsd/serial-relay.py` preserves the
long-lived QEMU socket while `bsd/freebsd-rpc.py` issues bounded RPC calls.

The arm64 proof booted an installed FreeBSD 15.1 system, extracted its matching
kernel source, compiled `kernel_lab_hello.ko`, loaded it with `kldload`,
and observed `KLAB_FREEBSD_SMOKE_OK`. Evidence is stored at
`library/bsd-evidence/freebsd-15.1-arm64/qemu10-module-smoke.log`.

## Expansion coverage

The post-floor expansion set also passes:

| Target | Architecture | Verified result |
| --- | --- | --- |
| FreeBSD 14.5-RELEASE | i386 | USERSPACE_PASS |
| FreeBSD 14.5-RELEASE | riscv64 | USERSPACE_PASS |
| NetBSD 11.0 | aarch64 | USERSPACE_PASS |
| DragonFly BSD 6.2.2 | x86_64 | USERSPACE_PASS |

FreeBSD i386 uses the stock loader's dual serial console mode. FreeBSD riscv64
uses the isolated QEMU 10 runtime defined by
`containers/qemu10-riscv64.Dockerfile`, with QEMU's matched OpenSBI firmware
and Debian's QEMU RISC-V U-Boot. Every run disables guest networking and uses a
disposable writable overlay over checksum-verified official media.
