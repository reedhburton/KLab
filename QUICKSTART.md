# KLab 1.0 quick start

KLab needs only two user-managed directories:

- `~/klab` is the default KLab root: installed targets, work state, suites, and results.
- `~/klab-offline` is the default portable repository of `.klab` artifacts.

## 1. One-time setup

For the default locations, no environment variables are needed:

```sh
./klab setup
./klab repo path
```

To use other locations:

```sh
export KLAB_ROOT=/fast-disk/klab
./klab setup --repo /archive/klab-offline
```

`setup` remembers the repository inside the selected KLab root. Install QEMU for the architectures you intend to run. Docker or Podman is needed only to capture some distribution targets on a connected staging machine.

## 2. Get or load a target

On a connected staging machine, pull a target into the offline repository:

```sh
./klab pull upstream:v6.6 --arch x86_64
./klab repo list
```

On an offline machine, copy or mount that repository and load it:

```sh
export KLAB_OFFLINE=1
./klab load /path/to/klab-offline
./klab targets
```

A single artifact can be loaded directly:

```sh
./klab load /path/to/ubuntu-24.04.klab
```

Loading verifies checksums and imports atomically. Removable archive files are staged automatically into the internal cache and are never deleted by cache pruning.

## 3. Build a kernel module

```sh
./klab build ubuntu:24.04:6.8.0-142-generic ./my-module -o ./out/module
```

A module directory normally contains its source and a kernel-module `Makefile`. Cross-architecture builds use the target architecture:

```sh
./klab build ubuntu:24.04:5.4.0-216-generic ./my-module \
  --arch aarch64 -o ./out/module-arm64
```

The original explicit form remains supported:

```sh
./klab build ubuntu:24.04:6.8.0-142-generic --module ./my-module -o ./out/module
```

## 4. Compile a userspace C program

```sh
./klab build-user ubuntu:24.04:6.8.0-142-generic ./client.c -o ./out/client
./klab build-user ubuntu:24.04:5.4.0-216-generic ./client.c \
  --arch aarch64 -o ./out/client-arm64
```

Compiler flags follow `--`:

```sh
./klab build-user upstream:v6.6 ./probe.c -o ./out/probe -- -O2 -Wall
```

## 5. Run a one-shot test

Before accepting a newly imported image, run the standard qualification gate:

```bash
./klab validate ubuntu:24.04:6.8.0-142-generic
```

This retains exact evidence under `KLAB_ROOT/results/image-validation`: target preflight, boot, real module insertion, concurrent and exec-replacement workloads, a cross-compiled userspace program, and a two-guest TCP payload/ACK exchange. Use `--level quick` for a boot-only check or `--level full` for those checks plus native-distribution conformance and a real SSH key login. A target is proven only at the level whose report records `RESULT=PASS`.

A target smoke test boots, validates the guest, and shuts it down:

```sh
./klab run ubuntu:24.04:6.8.0-142-generic
```

Create a reusable module suite, replace its generated module and `test.sh` with your test, then run it:

```sh
./klab suite create my-driver
./klab suite show my-driver
./klab run ubuntu:24.04:6.8.0-142-generic --suite my-driver
```

The equivalent explicit form is:

```sh
./klab suite run my-driver ubuntu:24.04:6.8.0-142-generic
```

## 6. Start and control a persistent guest

```sh
./klab start ubuntu:24.04:6.8.0-142-generic --name dev
./klab ps
./klab exec dev 'uname -a'
./klab push dev ./out/client /tmp/client
./klab exec dev 'chmod +x /tmp/client && /tmp/client'
./klab stop dev
```

Use `exec` for automation. For many interactive commands, use one SSH session to avoid per-command CLI startup overhead.

## 7. Start an SSH guest

Generate a key once if needed:

```sh
ssh-keygen -t ed25519 -f "$HOME/.ssh/klab" -N ''
```

Start a small Dropbear guest and connect:

```sh
./klab start ubuntu:24.04:6.8.0-142-generic \
  --userspace buildroot:ssh --name ssh-test \
  --ssh-auth key --ssh-key "$HOME/.ssh/klab" --ssh-port 2222
./klab shell ssh-test
./klab stop ssh-test
```

Bind SSH to the LAN only when explicitly required:

```sh
./klab start ubuntu:24.04:6.8.0-142-generic \
  --userspace buildroot:ssh --name lan-test \
  --ssh-auth key --ssh-key "$HOME/.ssh/klab" \
  --ssh-bind 0.0.0.0 --ssh-port 2222
```

## 8. Minimal versus native userspace

The default minimal guest is quickest and is suitable for module loading and portable static test programs:

```sh
./klab start ubuntu:24.04:6.8.0-142-generic --name minimal
```

Use a captured native userspace when distribution libraries, commands, package layout, or runtime linkage matter:

```sh
./klab start ubuntu:24.04:6.8.0-142-generic \
  --userspace native:ubuntu:24.04 --name native
./klab exec native 'cat /etc/os-release'
./klab stop native
```

Native SSH uses the distribution's OpenSSH server when available. If the native root has no usable `/usr/sbin/sshd`, KLab automatically injects a small architecture-matched static Dropbear server; the same `--ssh-auth key`, `password`, and `none` options work without changing the captured distribution libraries or package layout.

## 9. Legacy Linux and BSD

```sh
./klab legacy list
./klab legacy plan linux-2.6.32-x86_64
./klab bsd list
./klab bsd status
```

Example BSD target operations:

```sh
./klab pull freebsd:14.5-RELEASE:riscv64
./klab run freebsd:14.5-RELEASE:riscv64
```

## 10. Repository storage and removable disks

```sh
./klab repo volume-add /mnt/klab-archive-1
./klab repo volumes
./klab repo stage /mnt/klab-archive-1/targets/example.klab
./klab repo cache-status
./klab repo cache-prune --free-gib 20
```

The V1 contract is in `KLAB-1.0-CONTRACT.md`. Detailed diagnostic and automation commands remain available through `./klab advanced COMMAND` or `./klab help`.
