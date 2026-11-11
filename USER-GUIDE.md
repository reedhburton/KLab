# KLab user guide

This guide explains KLab from first setup through module development, userspace
compatibility testing, automated suites, offline operation, and CI containers.
Examples use the release-candidate command interface in this repository.

## 1. How KLab is organized

KLab separates the tool from its mutable data:

| Item | Default | Purpose |
|---|---|---|
| KLab source | Current checkout | CLI, providers, runners, examples, documentation |
| KLab root | `~/klab` | Imported targets, suites, sessions, caches, and results |
| Offline repository | `~/klab-offline` | Portable targets and shared dependencies |
| Suite | `$KLAB_ROOT/suites/NAME` | Test manifest, source, fixtures, and Bash controller |
| Results | `$KLAB_ROOT/results` | Reports, console logs, process output, and crash evidence |

A target identifies an operating-system kernel and architecture. Examples:

```text
upstream:v6.6                                  with --arch x86_64
ubuntu:24.04:6.8.0-85-generic                 with --arch x86_64
debian:bookworm:6.1.0-40-amd64                with --arch x86_64
fedora:43:6.17.1-300.fc43.x86_64              with --arch x86_64
freebsd:14.5-RELEASE:riscv64                  architecture is in the BSD ID
```

A `.klab` file describes one exact target. Large reusable dependencies may be
separate content-addressed files, such as exact build environments, distribution
toolchains, userspaces, sources, and SDKs. Transfer an entire repository or export
directory so these dependencies travel with the target.

### Runtime choices

KLab distinguishes the kernel from the guest userspace:

- `busybox-static` is the smallest legacy-compatible environment.
- `buildroot:minimal` is the default reproducible modern test environment.
- `buildroot:network` adds networking tools.
- `buildroot:ssh` adds Dropbear for interactive access.
- `native:PROVIDER:RELEASE` uses a captured distribution userspace.

The same exact kernel can be booted with different compatible userspaces. A native
Ubuntu root makes distribution-library results representative of Ubuntu. A Buildroot
root is faster and useful for kernel-module and static-program testing.

## 2. Host preparation

Run KLab from an extracted release archive or a source checkout:

```bash
tar -xf klab-release-candidate.tar.gz
cd klab-release-candidate
chmod +x klab kernel-lab.sh klab-*.sh
```

When working from Git, clone the project using the repository URL supplied by your
KLab distributor, enter the checkout, and use the same commands below. Keep mutable
target data outside the checkout through `KLAB_ROOT`.

A typical Debian or Ubuntu x86_64 staging and test host needs:

```bash
sudo apt update
sudo apt install -y \
  git build-essential bc bison flex libssl-dev libelf-dev \
  python3 perl file cpio gzip zstd xz-utils bzip2 tar \
  patch unzip rsync curl wget busybox-static \
  qemu-system-x86 qemu-utils
```

For ARM and AArch64:

```bash
sudo apt install -y qemu-system-arm qemu-efi-aarch64
```

Distribution target capture normally uses Docker or Podman:

```bash
sudo apt install -y docker.io
# or
sudo apt install -y podman
```

Check the current host:

```bash
./kernel-lab.sh doctor
./kernel-lab.sh architectures
./kernel-lab.sh userspaces
```

KVM makes native-architecture guests substantially faster. Emulated architectures
work without KVM but take longer.

## 3. Initial setup

Use the defaults:

```bash
./klab setup
./klab repo path
```

Or choose the two locations explicitly:

```bash
./klab setup \
  --root /fast/klab \
  --repo /archive/klab-offline
```

The root is remembered through `KLAB_ROOT`; the repository path is stored in the
root configuration. A common shell setup is:

```bash
export KLAB_ROOT=/fast/klab
```

Do not point several users at one writable KLab root. Give each user an independent
root and share the offline repository read-only.

## 4. Preparing and importing targets

### Connected staging machine

Pulling prepares a transferable target and updates the repository index:

```bash
./klab pull upstream:v6.6 --arch x86_64
./klab pull ubuntu:24.04:6.8.0-85-generic --arch x86_64
./klab repo list
```

A modern pull defaults to Buildroot minimal plus its SDK. Legacy Linux 2.x targets
select their compatible minimal userspace automatically.

### Offline worker

Copy, mount, or attach the repository, then:

```bash
export KLAB_OFFLINE=1
./klab setup --root "$HOME/klab" --repo /media/klab-offline
./klab load /media/klab-offline
./kernel-lab.sh targets
```

Load one artifact when its dependencies are already present:

```bash
./klab load /media/klab-offline/variants/ubuntu-example.klab
```

Imports verify checksums and install dependencies before targets. Interrupted imports
do not leave a target partially installed.

### Repository volumes and automatic staging

Register large removable volumes:

```bash
./klab repo volume-add /mnt/klab-store
./klab repo volume-add /mnt/klab-cache
./klab repo volumes
```

Stage an artifact into the active cache:

```bash
./klab repo stage /mnt/klab-store/targets/example.klab
./klab repo cache-status
./klab repo cache-prune --free-gib 40
```

Pruning removes staged cache copies, not the durable files on registered volumes.

## 5. Qualifying an image

KLab provides three qualification levels:

```bash
./klab validate TARGET --arch x86_64 --level quick
./klab validate TARGET --arch x86_64 --level standard
./klab validate TARGET --arch x86_64 --level full
```

- **quick** proves that the target boots.
- **standard** adds module build/insertion, concurrent and replacement-process
  workloads, a target userspace program, and two-guest TCP exchange.
- **full** adds native-distribution conformance and real SSH command execution.

A full PASS includes the standard gate. Availability in the catalog is not proof;
the retained report is the evidence. Reports live under:

```text
$KLAB_ROOT/results/image-validation/
```

A simple smoke run is:

```bash
./klab run ubuntu:24.04:6.8.0-85-generic --arch x86_64
```

## 6. Building kernel modules

A normal external module project contains a Kbuild-compatible Makefile:

```make
obj-m += demo.o
```

and source:

```c
#include <linux/init.h>
#include <linux/module.h>

static int __init demo_init(void)
{
    pr_info("demo: loaded\n");
    return 0;
}

static void __exit demo_exit(void)
{
    pr_info("demo: unloaded\n");
}

module_init(demo_init);
module_exit(demo_exit);
MODULE_LICENSE("GPL");
```

Build it for one target:

```bash
./klab build ubuntu:24.04:6.8.0-85-generic ./demo-module \
  --arch x86_64 -o ./out/ubuntu-2404
```

Cross-build using the target's architecture and captured compiler:

```bash
./klab build ubuntu:24.04:6.8.0-85-generic ./demo-module \
  --arch aarch64 -o ./out/ubuntu-2404-arm64
```

KLab binds exact distro-native build environments when required. It does not assume
that the compiler installed on the controller matches the compiler used for the
target kernel.

### Test the module in a persistent guest

```bash
./klab start ubuntu:24.04:6.8.0-85-generic --name module-test
./klab push module-test ./out/ubuntu-2404/demo.ko /tmp/demo.ko
./klab exec module-test 'insmod /tmp/demo.ko'
./klab exec module-test 'dmesg | tail -30'
./klab exec module-test 'rmmod demo'
./klab stop module-test
```

### A realistic module project

The open-source `v4l2loopback` driver is a useful modern integration example. It
exercises character devices, IOCTLs, streaming, module parameters, sysfs, and the
V4L2 subsystem:

```bash
git clone https://github.com/v4l2loopback/v4l2loopback.git
./klab build ubuntu:24.04:6.8.0-85-generic ./v4l2loopback \
  --arch x86_64 -o ./out/v4l2loopback
```

It is an additional modern gate rather than the universal baseline: a target must
enable V4L2, and current source does not cover every historical 2.x API. KLab's small
character-device fixtures remain appropriate for broad legacy coverage.

## 7. Building userspace programs

Compile a single C source with the target SDK:

```bash
./klab build-user ubuntu:24.04:6.8.0-85-generic ./probe.c \
  --arch x86_64 -o ./out/probe
```

Pass compiler flags after `--`:

```bash
./klab build-user upstream:v6.6 ./probe.c \
  -o ./out/probe -- -O2 -Wall -Wextra
```

Run it:

```bash
./klab start ubuntu:24.04:6.8.0-85-generic --name user-test
./klab push user-test ./out/probe /tmp/probe
./klab exec user-test 'chmod +x /tmp/probe && /tmp/probe'
./klab stop user-test
```

For multiple sources, headers, fixtures, or a precompiled binary, use a suite manifest
as described below.

## 8. Persistent guests and SSH

Start a guest:

```bash
./klab start ubuntu:24.04:6.8.0-85-generic --name dev
./klab ps
./klab exec dev 'uname -a'
./klab push dev ./config.json /tmp/config.json
./klab stop dev
```

`klab exec` blocks until its command exits. `klab start` returns after the guest
control service is ready. Persistent background programs should be managed with a
suite or started deliberately inside the guest.

### SSH with a key

```bash
ssh-keygen -t ed25519 -f "$HOME/.ssh/klab" -N ''

./klab start ubuntu:24.04:6.8.0-85-generic \
  --name ssh-dev --userspace buildroot:ssh \
  --ssh-auth key --ssh-key "$HOME/.ssh/klab" \
  --ssh-bind 127.0.0.1 --ssh-port 2222

./klab shell ssh-dev
./klab stop ssh-dev
```

### Password or intentionally passwordless

```bash
./klab start TARGET --name password-test \
  --userspace buildroot:ssh --ssh-auth password \
  --ssh-password 'temporary-test-password' --ssh-port 2222

./klab start TARGET --name isolated-test \
  --userspace buildroot:ssh --ssh-auth none --ssh-port 2222
```

Passwordless mode belongs on an isolated host-only connection. Binding to the LAN:

```bash
--ssh-bind 0.0.0.0
```

exposes the forwarded port on every host interface. Use key authentication, host
firewall rules, and a deliberately chosen port.

### Native userspace with SSH

```bash
./klab start ubuntu:24.04:6.8.0-85-generic \
  --userspace native:ubuntu:24.04 --name native-dev \
  --ssh-auth key --ssh-key "$HOME/.ssh/klab"
```

KLab uses the native OpenSSH server when viable. If the native root lacks one, it can
inject an architecture-matched static Dropbear without replacing native libraries.

## 9. Readable automated suites

Create a suite:

```bash
./klab suite create device-test
```

It creates:

```text
$KLAB_ROOT/suites/device-test/
├── klab.toml
├── test.sh
├── suite.json
├── scenario.json
└── hello-module/
```

The recommended interface is an artifact manifest plus ordinary controller-side Bash.
Only commands beginning with `klab exec`, `klab process`, `klab copy`/`push`,
or `klab module` enter a target.

### Manifest with a module and C project

```toml
[test]
script = "test.sh"
timeout = 300
userspace = "buildroot:minimal"

[module.driver]
source = "driver"
unload = true

[build.client]
sources = ["client/main.c", "client/protocol.c"]
flags = ["-O2", "-Iclient/include"]
static = true
target = "/tmp/client"

[file.request]
source = "fixtures/request.bin"
target = "/tmp/request.bin"
mode = "0644"
```

KLab exposes the resulting paths as:

```text
KLAB_MODULE_DRIVER
KLAB_BUILD_CLIENT
KLAB_FILE_REQUEST
```

### Simple module test

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

klab module load target driver
klab exec target -- /tmp/client --self-test
messages="$(klab exec target -- dmesg)"
klab expect contains "$messages" 'driver: self-test passed'
klab module unload target driver
```

### Two coordinated processes

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

klab module load target driver

klab process start target server -- /tmp/client --server
klab process ready target server stdout 'SERVER_READY' --timeout 20

klab process start target client -- /tmp/client --connect
klab process wait target client
klab process wait target server

client_output="$(klab process output target client stdout)"
server_output="$(klab process output target server stdout)"
klab expect contains "$client_output" 'CLIENT_OK'
klab expect contains "$server_output" 'SERVER_OK'
```

### Persistent Bash process and file producer

```bash
klab process start target reader -- sh -c \
  'echo $$ >/tmp/reader.pid
   while [ ! -f /tmp/input ]; do sleep .05; done
   value=$(cat /tmp/input)
   printf "reader saw: %s\n" "$value"
   exec /tmp/final-check "$value"'

klab process ready target reader file /tmp/reader.pid --timeout 10
klab process start target writer -- sh -c 'printf "hello\n" >/tmp/input'
klab process wait target writer
klab process wait target reader

output="$(klab process output target reader stdout)"
printf '%s\n' "$output" | grep -F 'reader saw: hello'
```

The reader's final `exec` replaces its shell and preserves the original process PID.

### Controller output versus target output

This runs `ps` inside the target, captures its stdout on the controller, and runs
the controller's `grep`:

```bash
ps_output="$(klab exec target -- ps ax)"
printf '%s\n' "$ps_output" | grep '[h]ttpd'
```

This sends the pipeline to the target, so the target must provide `grep`:

```bash
klab exec target 'ps ax | grep "[h]ttpd"'
```

Single quotes preserve target-side variables and substitutions:

```bash
klab exec target 'printf "%s\n" "$HOME"; uname -r'
```

Double quotes expand controller variables first:

```bash
case_name=network-17
klab exec target "printf '%s\n' '$case_name' >/tmp/case"
```

### Expected failures

```bash
klab exec target --expect-exit 2 -- /tmp/client --invalid
klab exec target --expect-exit 1,2 -- grep missing /tmp/data
klab exec target --expect-failure -- false
klab exec target --expect-timeout --timeout 1 -- sleep 30
```

An expected failure counts as success. The wrong failure or unexpected success fails
the test.

### Conditional behavior

Controller logic can select commands by target:

```bash
case "$KLAB_TARGET:$KLAB_ARCH" in
  freebsd:*|netbsd:*|openbsd:*|dragonfly:*)
    klab exec target -- kldstat
    ;;
  *:aarch64)
    klab exec target -- /tmp/client --unaligned-safe
    ;;
  *)
    klab exec target -- /tmp/client
    ;;
esac

if klab exec target -- sh -c 'command -v python3' >/dev/null 2>&1; then
  python=python3
else
  python=python2
fi
klab exec target -- "$python" /tmp/check.py
```

### Transfer files conditionally

```bash
klab copy target scripts/setup.sh /tmp/setup.sh
klab exec target 'chmod +x /tmp/setup.sh; /tmp/setup.sh'

if [[ "$KLAB_TARGET" == ubuntu:* ]]; then
  klab copy target packages/test.deb /tmp/test.deb
  klab exec target 'dpkg -i /tmp/test.deb'
fi
```

## 10. Running a suite across targets

Run directly:

```bash
./klab test device-test on \
  ubuntu:20.04:5.4.0-216-generic@x86_64 \
  ubuntu:22.04:5.15.0-176-generic@x86_64 \
  ubuntu:24.04:6.8.0-85-generic@x86_64
```

Use a target file:

```text
# targets.txt
ubuntu:20.04:5.4.0-216-generic@x86_64
ubuntu:22.04:5.15.0-176-generic@x86_64
ubuntu:24.04:6.8.0-85-generic@x86_64
```

```bash
./klab test device-test on @targets.txt
```

Queue a scenario suite:

```bash
./klab suite queue device-test --target-file targets.txt
./klab suite queue device-test --all
```

Preview without booting:

```bash
./klab suite queue device-test \
  --target-file targets.txt --dry-run --output /tmp/device-plan
```

Resume a partially completed queue:

```bash
./klab suite queue device-test \
  --target-file targets.txt --resume --output /srv/results/device-run-1
```

A failed target does not prevent later targets. `status.tsv` summarizes the matrix;
per-target directories retain exact plans and evidence.

## 11. Multi-guest and networking tests

KLab ships multi-guest scenarios under `examples/multiguest`. The simplest TCP
example starts a server and client in separate guests:

```bash
./kernel-lab.sh multiguest-run \
  ./examples/multiguest/two-guest-network.json \
  --report-dir ./results/two-guest-network
```

There are also examples for:

- Three guests spanning kernels or architectures
- Two LANs joined by a guest router
- Link flaps and recovery
- Delayed interfaces and packet capture
- Mixed x86_64, i386, AArch64, ARMv7, MIPS, and MIPSel guests
- Guest power interruption
- Intentional panic isolation

Use `--dry-run` to inspect a generated plan before launching QEMU.

## 12. Intentional panic and crash evidence

The shipped panic scenario loads a module that deliberately panics its disposable
guest:

```bash
./kernel-lab.sh scenario-run \
  ./examples/scenarios/intentional-kernel-panic.json \
  --report-dir ./results/intentional-panic
```

Never load the panic module into the host kernel. KLab checks for fresh console and
suite-specific panic evidence. Optional QEMU memory dumps are enabled with the
crashdump controls documented by `kernel-lab.sh help`.

Inspect retained crashes:

```bash
./kernel-lab.sh crashes
./kernel-lab.sh crash-info CRASH_ID
```

## 13. Legacy kernels

List the formal legacy ladder:

```bash
./klab legacy list
./klab legacy plan linux-2.6.32-x86_64
```

Legacy success is graded:

```text
SOURCE_VERIFIED → BUILD_PASS → BOOT_PASS → USERSPACE_PASS
                → MODULE_PASS → NETWORK_PASS
```

Very old kernels cannot always support modern SSH or native userspace. KLab uses
compatible BusyBox and historical Dropbear/OpenSSH paths where technically possible
and records the achieved gate instead of pretending all targets are equivalent.

## 14. BSD targets

List the catalog and status:

```bash
./klab bsd list
./klab bsd status
```

Pull and run a cataloged target:

```bash
./klab pull freebsd:14.5-RELEASE:riscv64
./klab run freebsd:14.5-RELEASE:riscv64 --mode full
```

BSD run modes are `minimal`, `ssh`, and `full`. Architecture is part of the
target ID. Linux modules are not portable to BSD; BSD tests use native module and
userspace interfaces.

## 15. Selective container exports

Create a portable image containing KLab and only chosen targets:

```bash
./klab export container \
  --target ubuntu:22.04:5.15.0-176-generic@x86_64 \
  --target ubuntu:24.04:6.8.0-85-generic@x86_64 \
  --profile full \
  --tag example/klab-ubuntu:rc \
  --output klab-ubuntu.oci.tar
```

Or use a file:

```bash
./klab export container \
  --targets-file targets.txt \
  --profile build \
  --output klab-build-matrix.oci.tar
```

Profiles:

| Profile | Intended use |
|---|---|
| `userspace` | Native runtime and basic tool compatibility |
| `build` | Module/userspace compilation and fast pipeline checks |
| `full` | Complete QEMU, SSH, module insertion, and validation |

Review a generated build context without building:

```bash
./klab export container \
  --target ubuntu:24.04:6.8.0-85-generic@x86_64 \
  --profile full --context-only /tmp/klab-container-context
```

Load and inspect an archive:

```bash
podman load -i klab-ubuntu.oci.tar
podman run --rm -it example/klab-ubuntu:rc targets
```

Run a full guest from the container with KVM access:

```bash
podman run --rm -it --device /dev/kvm \
  -v "$PWD:/workspace" \
  example/klab-ubuntu:rc \
  run ubuntu:22.04:5.15.0-176-generic --arch x86_64
```

A container shares its host kernel. It may compile for any packaged target, but
`insmod` inside an ordinary container would affect the host and only works for a
matching host kernel. Use KLab's QEMU guest for authoritative module insertion.

+
## Web dashboard and hosted artifact repository

Start a local read-only dashboard:

```bash
./klab serve
```

Open [http://127.0.0.1:8080](http://127.0.0.1:8080). The page displays imported
targets, running and stopped guest sessions, recent suite queues, result counts, and
downloadable artifacts from the configured offline repository.

Host the read-only repository on a LAN:

```bash
./klab serve --bind 0.0.0.0 --port 8080
```

Binding to `0.0.0.0` makes target metadata and artifacts reachable through every
host interface. Apply host firewall rules and use TLS when crossing a trusted local
network boundary.

Enable authenticated artifact uploads:

```bash
umask 077
openssl rand -hex 32 > "$HOME/.config/klab-upload-token"

./klab serve --bind 0.0.0.0 --port 8443 \
  --upload-token-file "$HOME/.config/klab-upload-token" \
  --tls-cert /path/to/fullchain.pem \
  --tls-key /path/to/private-key.pem
```

Upload atomically with an optional checksum assertion:

```bash
artifact=ubuntu-example.klab
sha="$(sha256sum "$artifact" | awk '{print $1}')"
token="$(cat "$HOME/.config/klab-upload-token")"

curl --fail --request PUT \
  -H "Authorization: Bearer $token" \
  -H "X-KLab-SHA256: $sha" \
  --data-binary "@$artifact" \
  "https://klab-host:8443/api/artifacts/incoming/$artifact"
```

Uploads are disabled unless a token file is supplied. The server writes to a temporary
file, checks the optional SHA-256 value, calls `fsync`, and atomically renames the
completed artifact. Paths cannot escape the configured repository.

Automation endpoints:

```text
GET  /healthz
GET  /api/status
GET  /api/targets
GET  /api/jobs
GET  /api/artifacts
GET  /repo/PATH
HEAD /repo/PATH
PUT  /api/artifacts/PATH
```

Artifact downloads support HTTP byte ranges, which allows interrupted large downloads
to resume:

```bash
curl --continue-at - --remote-name \
  http://klab-host:8080/repo/variants/ubuntu-example.klab
./klab load ./ubuntu-example.klab
```

The server reads KLab state and repository files directly, so the dashboard updates
without a separate database. The default localhost, read-only configuration is the
recommended development mode.


## 17. Multiple users and CI

Each user or CI job should have its own root:

```bash
KLAB_ROOT="$RUNNER_TEMP/klab-$CI_JOB_ID" \
KLAB_REPO=/srv/klab-offline \
  ./klab test device-test on @targets.txt
```

The repository can be shared read-only. One maintainer should handle pulls, indexing,
pruning, and volume changes. Queue IDs contain time, UID, PID, and randomness, so
independent roots can submit simultaneously.

A practical pipeline has two stages:

1. Run parallel container compilation and userspace checks.
2. Send successful builds to serialized or capacity-limited QEMU validation.

This rejects elementary failures before consuming VM time while retaining real-kernel
evidence for release decisions.

## 18. Results and troubleshooting

Useful commands:

```bash
./kernel-lab.sh status
./kernel-lab.sh doctor
./kernel-lab.sh targets
./klab ps
./klab repo cache-status
```

Common problems:

### Target is not installed

```text
no imported target
```

Run `klab load REPOSITORY` on the worker. On staging, run `klab pull TARGET`.

### Module format or vermagic mismatch

Build against the exact target ID and architecture. Do not reuse one `.ko` across
different ABI releases or flavors merely because their upstream base version matches.

### SSH does not become ready

Confirm that the chosen userspace supports SSH, select an unused host port, and review
the session console. Native roots fall back to Dropbear when supported.

### Cross-architecture program gives exec format error

System QEMU boots do not depend on host `binfmt_misc`. Container execution of a
foreign userspace does. Register the relevant user-mode QEMU interpreter or perform
the test inside a full-system KLab guest.

### Guest is slow

Use KVM for same-architecture guests, keep sessions running while issuing several
commands, use controller suites instead of repeatedly booting, and reserve full
validation for artifacts that passed container compilation.

### Disk usage grows

```bash
./klab repo cache-status
./klab repo cache-prune --free-gib 40
```

Keep the durable offline repository on large storage and the active kernel/build cache
on fast storage.

### A test fails

Start with the matrix `status.tsv`, then inspect the target report, build log,
console, process stdout/stderr, and dmesg. KLab preserves prior attempts so a retry
does not erase the evidence that motivated a fix.

## 19. Advanced interface

The simple `klab` CLI covers normal workflows. Detailed operations remain available:

```bash
./klab advanced targets
./klab advanced capabilities TARGET
./kernel-lab.sh help
```

Use the advanced interface for provider development, architecture bring-up, explicit
scenario JSON, crash controls, and diagnostics. Scripts intended for users should
prefer the stable simple commands whenever they provide the needed operation.
