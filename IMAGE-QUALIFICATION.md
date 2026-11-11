# KLab image qualification

Use one command after importing or preparing a new Linux image:

```sh
./klab validate TARGET [--arch ARCH] [--level quick|standard|full]
```

The default is `standard`. A run creates a unique report below `KLAB_ROOT/results/image-validation` unless `--report-dir DIR` is supplied. The claim is valid only when that report's `RESULT` file says `PASS`; `gates.tsv` and `manifest.json` bind the claim to the exact target, architecture, requested level, and evidence logs.

## Levels

- `quick`: target metadata/preflight plus a real QEMU boot, exact guest identity check, agent command path, and clean shutdown.
- `standard`: quick plus compilation and real insertion of `tests/all-five/module`, concurrent access to its live sysfs parameter, shell process replacement through `exec`, cross-compilation of `examples/network-pair.c`, two simultaneous guests on an isolated LAN, and an exact TCP payload/ACK exchange.
- `full`: standard plus the matching native distribution userspace, all native guest conformance probes, automatic OpenSSH/Dropbear startup, and a real host-to-guest SSH key login that verifies the exact kernel release. For distro targets, the native userspace is inferred as `native:PROVIDER:RELEASE`; use `--userspace SPEC` to override it.

The standard TCP gate deliberately starts two sessions from the already installed bundle and sealed SDK. It does not call `prepare`, access the network, or recapture a toolchain.

FreeBSD targets use backend-native gates: source-backed module build/load/unload, persistent native userspace, filesystem/kernel/process/toolchain/runtime/network/module/shutdown probes, and real SSH for `full`. Linux distro targets use matching native captures; upstream/custom Linux targets use Buildroot SSH and its portable conformance probes.

## Examples

```sh
./klab validate ubuntu:24.04:6.8.0-142-generic
./klab validate ubuntu:24.04:6.8.0-142-generic --level full
./klab validate ubuntu:24.04:6.8.0-142-generic --arch aarch64 --level standard
./klab validate upstream:v2.6.32.71 --arch x86_64 --level quick
```

A failed gate does not erase earlier evidence. Inspect the corresponding path in `gates.tsv`, fix the image or KLab, and use a new report directory for the retry.
