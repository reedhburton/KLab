# KLab r15 — Multi-Guest Network Scenarios

## Purpose

r15 extends the r14 single-guest coordinated process framework into multiple simultaneously running KLab guests on one deterministic private Ethernet segment.

The design is deliberately layered:

1. **Simple:** two guests, one server and one client, same kernel/architecture, one cross-guest gate, one TCP exchange.
2. **Complex:** arbitrary guest count, per-guest kernel/architecture/profile, per-guest modules and cross-compiled userspace, shared cross-guest gates, failure-tolerant collection, and one merged timeline/report.

## Network backend

KLab uses QEMU's socket multicast network backend for the first implementation. It is host-local, requires no TAP/bridge creation and no root privileges, and lets several QEMU processes share one emulated Ethernet bus.

Each guest receives:

- a static IPv4 CIDR address,
- a deterministic locally administered MAC address,
- an architecture-specific emulated NIC,
- no default gateway unless a future scenario explicitly adds one.

Initial NIC profiles:

| Architecture | QEMU NIC |
|---|---|
| x86_64 | e1000 |
| i386 | e1000 |
| aarch64 | virtio-net-device |
| armv7 | virtio-net-device |
| mips | pcnet |
| mipsel | pcnet |

The kernel configuration path explicitly enables networking plus the relevant NIC driver as built-in functionality so the initramfs can configure the interface without loading an external driver module.

## Session identity fix

Prior KLab session control/QMP socket paths were derived from target + architecture + profile. Two sessions with identical target tuples could collide even when they had different session names.

r15 includes the session name in the socket hash. This is required for two guests running the exact same kernel, which is a normal multi-process/network test case.

## Cross-guest gates

r14 barriers were guest-local. r15 adds guest-agent gates:

- `gate NAME PARTICIPANT TIMEOUT`
- `gate-status NAME PARTICIPANT`
- `gate-release NAME`
- `gate-run64 NAME PARTICIPANT TIMEOUT COMMAND64`

A gated process creates a waiter marker inside its guest and blocks. The host waits until every declared participant across all guests reports `WAITING`, then releases the named gate on all participating guests. This produces a real cross-VM synchronization point without requiring clock synchronization or a guest network control daemon.

## Scenario schema

Schema: `klab-multiguest-scenario-v1`

Each guest may independently declare:

- target kernel,
- target architecture,
- profile/userspace,
- IP/MAC,
- cross-compiled builds,
- uploaded files,
- kernel modules,
- named processes,
- process expected exit codes,
- cross-guest gates and timeouts.

Example command:

```bash
./kernel-lab.sh multiguest-run examples/multiguest/two-guest-network.json
```

Dry-run:

```bash
./kernel-lab.sh multiguest-run examples/multiguest/three-guest-mixed-arch.json --dry-run
```

## Simple example

`examples/multiguest/two-guest-network.json`

- server: upstream v6.6 / x86_64 / 10.77.0.11
- client: upstream v6.6 / x86_64 / 10.77.0.12
- both cross-compile the same static `network-pair` binary
- both wait at gate `start`
- host releases both guests
- server accepts one TCP client
- client sends a payload and verifies the ACK
- both exit 0

This proves duplicate-kernel concurrent sessions, L2/L3 guest networking, cross-guest synchronization, target-native user binaries, and merged reporting.

## Complex kernel-span example

`examples/multiguest/three-guest-kernel-span.json`

- server: upstream v6.6
- client-old: upstream v5.4
- client-new: upstream v7.0
- all x86_64 initially
- server loads the hello kernel module
- all three processes synchronize on one host-controlled gate
- server accepts two clients
- both clients exchange unique payloads
- module is unloaded during teardown
- output/events/dmesg from all guests are retained

## Mixed-architecture example

`examples/multiguest/three-guest-mixed-arch.json`

- x86_64 server
- aarch64 client
- i386 client
- all use upstream v6.6

The same C source is independently cross-compiled using each guest's target SDK. The test therefore exercises the architecture-independent scenario layer and the cross-toolchain/runtime layer simultaneously.

## Canonical report

Schema: `klab-multiguest-report-v1`

The report contains:

- normalized scenario,
- network CIDR and QEMU bus identity,
- every guest target/architecture/IP/MAC/session,
- process expected/actual exit/signal/wait result,
- process stdout/stderr paths,
- module load/unload results,
- per-guest dmesg,
- per-guest final network state,
- guest-agent events,
- host orchestration events,
- one time-ordered merged timeline,
- final result and last completed stage.

## Failure behavior

- A guest boot failure stops the scenario and tears down already-started sessions.
- A module load failure is recorded but does not prevent collection of userspace evidence where possible.
- Process failures/timeouts are accumulated so other processes can still be collected.
- Module unload failures are part of the final result.
- `--keep-sessions` preserves running guests for interactive debugging.

## Overnight runner

`klab-multiguest-overnight-r15.sh` runs:

1. simple two-guest network scenario,
2. complex three-kernel scenario,
3. mixed x86_64/aarch64/i386 scenario by default.

The runner:

- preflights required QEMU binaries,
- records `SKIP_QEMU` instead of performing expensive preparation when an emulator is unavailable,
- continues after case failures,
- supports `KLAB_MULTIGUEST_RESUME_RUN_ID=latest`,
- does not duplicate completed rows on resume,
- creates a compact results tarball.

Disable mixed-architecture testing with:

```bash
KLAB_MULTIGUEST_MIXED_ARCH=0 ./klab-multiguest-overnight-r15.sh
```

## Current validation boundary

The scenario parser, gate protocol, network-test program, report generation, architecture NIC model, dry runs, and overnight resume logic are locally validated. The development environment used for this checkpoint has no `qemu-system-*` binaries, so actual multi-VM Ethernet traffic remains a host-side validation item for the next run.
