# KLab 1.0 product contract

KLab 1.0 has two user-managed locations:

- `KLAB_ROOT` (default `~/klab`): installed targets, toolchains, suites, work state, and results.
- `KLAB_REPO` (default `~/klab-offline`): portable `.klab` artifacts and `INDEX.tsv`.

Caches, sessions, logs, build directories, and artifact stores are implementation details below `KLAB_ROOT`. Users do not coordinate them.

## Stable command surface

```sh
klab setup [--root DIR] [--repo DIR]
klab pull TARGET [--arch ARCH]
klab load [FILE.klab|REPOSITORY]
klab build TARGET --module DIR [--arch ARCH] [-o DIR]
klab run TARGET [--arch ARCH]
klab run TARGET --suite NAME [--arch ARCH]
klab suite create NAME
klab suite list
klab suite show NAME
klab suite run NAME TARGET [--arch ARCH]
klab repo path|list|index
klab legacy list
klab legacy plan ID
klab bsd list
klab bsd status
```

`pull` creates a transfer-complete artifact with Buildroot minimal userspace, its SDK, and a bound toolchain when applicable, then indexes the offline repository. `load` verifies and atomically imports artifacts. `build` builds a module. `run` boots and exercises the built-in smoke test or a named suite.

For cataloged BSD expansion targets, the same `pull` command downloads and
verifies official media into `KLAB_REPO/bsd`; `run` boots a disposable overlay
and saves evidence beneath `KLAB_ROOT/results/bsd`. Architecture is part of the
BSD target identifier, for example:

```sh
klab pull freebsd:14.5-RELEASE:riscv64
klab run freebsd:14.5-RELEASE:riscv64
```

The initial simple BSD catalog covers FreeBSD 14.5 i386 and riscv64, NetBSD
11.0 aarch64, and DragonFly BSD 6.2.2 x86_64. `klab bsd list` prints the
catalog, while `klab bsd status` reports the complete BSD validation matrix.

Existing detailed commands remain available for automation and debugging through `klab advanced COMMAND ...`; non-conflicting historical commands also continue to pass through directly. They are outside the small 1.0 user contract.

## Required platform gates

Modern Linux must pass fresh-root offline import, repack, build, boot, userspace, module, networking, and multi-process tests on x86_64, i386, AArch64, ARMv7, MIPSel, and big-endian MIPS.

Linux 2.x is a 1.0 requirement. The required ladder lives in `legacy/targets-v1.json`. Results are graded rather than all-or-nothing: `SOURCE_VERIFIED`, `BUILD_PASS`, `BOOT_PASS`, `USERSPACE_PASS`, `MODULE_PASS`, and `NETWORK_PASS`. Each manifest row declares its minimum 1.0 gate. Linux 2.0.40/i386 must boot; representative 2.2/2.4 targets must reach userspace/module gates; Linux 2.6.32 on i386 and x86_64 must reach networking.

## Compatibility guarantees

- A 1.x reader verifies and either imports a supported artifact or rejects it without modifying an installed target.
- Failed and interrupted imports leave no partial target.
- A successful imported target can be repacked without network access.
- Suite manifests use an explicit schema and reject escaping paths.
- Experimental platforms remain clearly labeled and do not silently weaken a required gate.
