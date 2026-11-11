# KLab 0.0.0b beta quick start

KLab prepares portable kernel targets on a connected staging machine and imports them into an isolated machine for network-free module builds and QEMU tests. Transfer the entire target directory: a distro `.klab` may depend on sibling `.klabbuildenv` and `.klabdistrotoolchain` files.

## Supported beta paths

Validated end to end on x86_64: Ubuntu, Fedora 43, Debian 12, and Alpine 3.23. Upstream kernel.org targets are validated on x86_64, i386, aarch64, armv7, mipsel, and big-endian mips subject to the installed QEMU/toolchain prerequisites. Historical releases vary with repository availability and compiler compatibility.

## Host prerequisites

A connected staging host needs Bash, Python 3, Git, curl/wget, tar, zstd, sha256sum, Docker or Podman, QEMU, cpio, and common build tools. On Debian/Ubuntu, a practical starting set is:

```bash
sudo apt install bash python3 git curl tar zstd coreutils docker.io qemu-system-x86 cpio make gcc
```

The offline host needs the same basic archive tools and QEMU. Docker/Podman is not used for imported hermetic module builds.

## Install or run in place

```bash
tar -xzf klab-0.0.0b.tar.gz
cd klab-0.0.0b
./klab architectures
./klab providers
```

The scripts can run in place. `install-m2.sh` remains available for a local installation if desired.

## Create another target on a connected machine

List exact releases first:

```bash
./klab list ubuntu:24.04 6.8
./klab list fedora:43 7.2
./klab list alpine:3.23
```

Create a complete transfer set:

```bash
./beta-tools/prepare-target.sh \
  ubuntu:24.04:6.8.0-142-generic \
  "$PWD/transfer-repo"

./beta-tools/prepare-target.sh \
  alpine:3.23:6.18.53-0-lts \
  "$PWD/transfer-repo"

./beta-tools/prepare-target.sh \
  upstream:v6.6 \
  "$PWD/transfer-repo"
```

Distro targets automatically capture their native GCC/binutils and sealed build root. Upstream targets use KLab's upstream toolchain resolution. Copy the whole `transfer-repo` directory to the offline machine.

## Import and use targets offline

Disconnect the destination from the network, then verify and import everything:

```bash
./beta-tools/offline-import.sh /media/transfer-repo "$PWD/offline-root"
```

Build the included example module using only imported artifacts:

```bash
./beta-tools/offline-build-module.sh \
  alpine:3.23:6.18.53-0-lts \
  "$PWD/examples/hello-module" \
  "$PWD/module-output" \
  "$PWD/offline-root"
```

Boot the imported kernel in QEMU, load the generated smoke module, and require a guest PASS marker:

```bash
./beta-tools/offline-smoke.sh \
  alpine:3.23:6.18.53-0-lts \
  "$PWD/offline-root"

# Non-x86 targets take an explicit architecture:
./beta-tools/offline-smoke.sh upstream:v5.15 "$PWD/offline-root" mipsel
```

The same commands work with Ubuntu, Fedora, Debian, and upstream target IDs shown by:

```bash
KLAB_ROOT="$PWD/offline-root" KLAB_HOME="$PWD/offline-root" ./klab targets
```

## Rebuild a `.klab` archive offline

After import, KLab can repack the cached target without network access:

```bash
./beta-tools/offline-repack-klab.sh \
  alpine:3.23:6.18.53-0-lts \
  "$PWD/rebuilt-alpine.klab" \
  "$PWD/offline-root"

# Repack a non-x86 target by passing its architecture:
./beta-tools/offline-repack-klab.sh upstream:v5.15 "$PWD/rebuilt-mipsel.klab" "$PWD/offline-root" mipsel
```

The helper verifies the rebuilt archive. Keep the corresponding `.klabbuildenv` and `.klabdistrotoolchain` files with a distro `.klab` when transferring it to another fresh root.

## Maintain a local target repository

```bash
./beta-tools/index-repository.sh /srv/klab-targets
sha256sum -c /srv/klab-targets/INDEX.tsv.sha256
```

`INDEX.tsv` records the target ID, architecture, byte size, SHA-256, and filename. The repository is a directory transport rather than an HTTP package server; import it with `offline-import.sh`.

## Direct commands

```bash
./klab verify target.klab
./klab inspect target.klab
./klab targets
./klab info TARGET
./klab build-module TARGET --module DIR -o OUTPUT_DIR
./klab smoke TARGET
```

Use `KLAB_ROOT` and `KLAB_HOME` to select a staging or offline root. Set both to the same absolute directory for predictable isolation.

## Beta limitations

- Distro acquisition is currently validated on x86_64.
- A `.klab` alone may reference sibling build-environment and native-toolchain artifacts; transfer the full directory.
- Repository retention and disk use are significant. The current 30-target corpus is about 16 GiB.
- Some historical Fedora and upstream targets fail because their repositories, tags, or old compiler requirements need further compatibility work. Failures do not invalidate verified artifacts already in the repository.
