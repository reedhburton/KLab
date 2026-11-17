# KLab

KLab is a portable kernel and operating-system compatibility lab. It prepares exact
kernel targets, captures their build dependencies and userspaces, transfers them to
offline machines, builds kernel modules and C programs, boots isolated guests, and
runs repeatable compatibility suites.

The current tree is **KLab 1.0.0**. Its 137-entry upstream
kernel/architecture matrix has complete live validation evidence. The wider target
catalog is also visible, with each entry labeled so packaged or experimental targets
are not mistaken for fully validated support.

## What KLab tests

- External kernel-module compilation against exact target headers and compilers
- Module insertion, removal, logs, and intentional panic capture in QEMU
- Native and minimal userspace programs
- Persistent, ordered, and concurrent process workflows
- Multi-guest TCP/IP and routed-network scenarios
- Interactive SSH access through OpenSSH or Dropbear
- Linux across current, historical, legacy, and multiple architecture targets
- Cataloged FreeBSD, NetBSD, OpenBSD, and DragonFly BSD targets
- Completely offline reconstruction from portable artifacts
- Selective OCI images containing KLab and chosen targets for CI

Containers provide fast userspace and compilation checks. QEMU supplies the actual
target kernel for module insertion, boot, panic, and kernel-behavior testing.

## Start here

The normal setup has only two user-managed locations:

- `KLAB_ROOT`, defaulting to `~/klab`, contains installed targets, suites,
  sessions, work state, and results.
- The offline repository, defaulting to `~/klab-offline`, contains portable
  `.klab` targets and shared artifacts.

```bash
./klab setup
./klab pull upstream:v6.6 --arch x86_64
./klab load
./klab validate upstream:v6.6 --arch x86_64 --level full
```

For a distribution kernel:

```bash
./klab pull ubuntu:24.04:6.8.0-142-generic --arch x86_64
./klab load
./klab build ubuntu:24.04:6.8.0-142-generic ./examples/hello-module
./klab run ubuntu:24.04:6.8.0-142-generic
```

## Find a target

Use the CLI for targets available on the current machine:

```bash
./klab targets       # imported and immediately runnable targets
./klab repo list     # portable targets in the configured offline repository
```

Use **[TARGETS.md](TARGETS.md)** to browse target families, understand validation
states, and filter the complete **[machine-readable catalog](catalog/current-target-inventory-2026-11-16.tsv)**.
A target ID includes the provider, release, and exact kernel when applicable:

```text
upstream:v6.6
ubuntu:24.04:6.8.0-142-generic
debian:bookworm:6.1.0-53-amd64
fedora:43:7.2.7-100.fc43.x86_64
freebsd:14.5-RELEASE:x86_64
```

`validated` means current test evidence exists. `packaged` means a portable artifact
exists but does not claim every release gate. `local` means files are present in this
lab and may still require packaging or validation.

## Common commands

```text
klab setup [--root DIR] [--repo DIR]
klab pull TARGET [--arch ARCH]
klab load [FILE.klab|REPOSITORY]
klab validate TARGET [--arch ARCH] [--level quick|standard|full]
klab build TARGET MODULE_DIR [--arch ARCH] [-o DIR]
klab build-user TARGET SOURCE.c [--arch ARCH] [-o FILE]
klab run TARGET [--arch ARCH]
klab start TARGET --name SESSION [boot and SSH options]
klab exec SESSION COMMAND
klab push SESSION LOCAL [REMOTE]
klab shell SESSION
klab stop SESSION
klab suite create NAME
klab test SUITE on TARGET@ARCH [TARGET@ARCH ...]
klab suite queue NAME [--target TARGET@ARCH|--target-file FILE|--all]
klab export container --target TARGET@ARCH [--target ...]
klab serve [--bind ADDRESS] [--port PORT] [--upload-token-file FILE]
klab repo <path|list|index|volume-add|volumes|stage|cache-status|cache-prune>
klab legacy <list|plan ID>
klab bsd <list|status>
```

## Example: persistent guest with SSH

```bash
ssh-keygen -t ed25519 -f "$HOME/.ssh/klab" -N ''

./klab start ubuntu:24.04:6.8.0-142-generic \
  --name ubuntu-test \
  --userspace native:ubuntu:24.04 \
  --ssh-auth key --ssh-key "$HOME/.ssh/klab" \
  --ssh-port 2222

./klab exec ubuntu-test 'cat /etc/os-release'
./klab shell ubuntu-test
./klab stop ubuntu-test
```

## Example: a compatibility suite

```bash
./klab suite create driver-test
$EDITOR "$HOME/klab/suites/driver-test/klab.toml"
$EDITOR "$HOME/klab/suites/driver-test/test.sh"

./klab test driver-test on \
  ubuntu:22.04:5.15.0-176-generic@x86_64 \
  ubuntu:24.04:6.8.0-142-generic@x86_64
```

Suite scripts are ordinary controller-side Bash. Target execution is explicit:

```bash
klab module load target driver
kernel="$(klab exec target -- uname -r)"
processes="$(klab exec target -- ps ax)"
printf '%s\n' "$processes" | grep '[m]y-daemon'
```

This makes it clear which shell performs variables, loops, `grep`, and `sed`.
See [USER-GUIDE.md](USER-GUIDE.md) for complete suite examples.

## Example: selective CI container

```bash
./klab export container \
  --target ubuntu:22.04:5.15.0-176-generic@x86_64 \
  --target ubuntu:24.04:6.8.0-142-generic@x86_64 \
  --profile full \
  --output klab-ubuntu-ci.oci.tar
```

The image contains only the selected targets and their referenced dependencies.
Use the `userspace` or `build` profile for smaller, faster pipeline images.
Module insertion still requires a matching host kernel or the included QEMU guest.

## Documentation

- **[USER-GUIDE.md](USER-GUIDE.md)** — installation, workflows, examples, suites,
  containers, offline operation, and troubleshooting
- [QUICKSTART.md](QUICKSTART.md) — concise first-use workflow
- **[TARGETS.md](TARGETS.md)** — target discovery, states, families, and filtering
- [CONTROLLER-TESTS.md](CONTROLLER-TESTS.md) — readable Bash suite language
- [TEST-SUITES.md](TEST-SUITES.md) — scenario and queue internals
- [IMAGE-QUALIFICATION.md](IMAGE-QUALIFICATION.md) — standard and full gates
- [NATIVE-GUEST-CONTRACT.md](NATIVE-GUEST-CONTRACT.md) — native userspace behavior
- [MULTIGUEST-NETWORK-R15.md](MULTIGUEST-NETWORK-R15.md) — multi-guest networking
- [BSD-V1-FLOOR.md](BSD-V1-FLOOR.md) — BSD support floor
- [KLAB-1.0-CONTRACT.md](KLAB-1.0-CONTRACT.md) — stable product contract

## Safety and evidence

KLab loads test modules only into disposable QEMU guests unless a user deliberately
runs a matching-kernel privileged container. Intentional panic tests must use isolated
guests. Reports, console logs, process output, build logs, hashes, and validation
results are retained beneath `$KLAB_ROOT/results`.

Run KLab as a normal user. Host package isolation uses Docker or Podman; QEMU/KVM
access may require membership in the host's virtualization group.

## Versioned offline repository releases

Repository releases are immutable and versioned independently from the KLab application. A snapshot records the KLab source commit, bundle format, every file hash, its parent release, and the exact changed-file set.

Create and export the first shipment:

```bash
klab repo snapshot lab-2026-10
klab repo export-release lab-2026-10 -o lab-2026-10.tar.zst
```

After adding targets, create a parent-linked delta containing only new or changed files:

```bash
klab repo snapshot lab-2026-11 --parent lab-2026-10
klab repo export-release lab-2026-11 -o lab-2026-11.delta.tar.zst
```

On the offline system, apply the base and then each delta in order:

```bash
klab repo apply-release lab-2026-10.tar.zst
klab repo apply-release lab-2026-11.delta.tar.zst
klab repo releases
```

A delta is rejected unless its declared parent was applied. Applying the same release again is safe. Removed files are recorded but retained by default; pass `--apply-removals` only when mirroring deletions is intended. Create snapshots only while repository writers are stopped; snapshot creation aborts if a file changes while it is hashed.
