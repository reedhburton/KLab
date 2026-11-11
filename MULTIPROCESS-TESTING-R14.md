# KLab r14 — coordinated multi-process testing

## Scope

r14 adds the first architecture-neutral coordinated test layer on top of the
existing KLab kernel/Buildroot/QEMU session machinery.  The initial execution
scope is one Linux guest with multiple coordinated processes and optional
kernel modules.  Multi-guest/network orchestration is intentionally deferred;
the v1 protocol is designed so the host coordinator can later address more
than one guest without changing process/barrier semantics.

## Scenario contract

Scenarios use `schema: klab-scenario-v1` and declare:

- upstream Linux target and target architecture;
- Buildroot userspace/profile;
- C sources to cross-compile with the target SDK;
- arbitrary files to push into the guest;
- kernel-module source directories and optional module arguments;
- named processes, expected exit codes and timeouts;
- optional named start barriers shared by multiple processes;
- report collection controls.

The bundled `examples/scenarios/multiprocess-basic.json` cross-compiles one
static worker, builds/loads the hello module, starts three worker processes,
releases all three through the `start` barrier, verifies independent exit
codes, collects stdout/stderr/events/dmesg, then unloads the module.

Run a scenario with:

```bash
./kernel-lab.sh scenario-run examples/scenarios/multiprocess-basic.json
```

Use `--dry-run` to validate the scenario and architecture plan without an
expensive kernel/rootfs/QEMU run.

## Guest agent

`guest-agent/klab-agent.c` is intentionally small and static-link friendly. It
runs inside the target guest and provides:

- daemon start/ping/shutdown;
- process spawn by base64-encoded shell command;
- process groups and signals;
- wait/status with timeout and exit/signal state;
- per-process stdout/stderr capture;
- named filesystem-backed barriers;
- barrier-and-exec (`barrier-run64`);
- timestamped named events.

The daemon exports its socket/state paths to children, so test programs and
shell wrappers can emit events without architecture-specific plumbing.

## Reporting

The canonical report is `report.json` (`klab-scenario-report-v1`). It includes:

- normalized scenario;
- architecture plan;
- per-process expected/actual exit, signal, wait result and stdout/stderr paths;
- module load/unload results;
- timestamped agent events;
- SHA-256/size metadata for generated user binaries, modules and guest agent;
- final dmesg path;
- final result and last completed stage.

A human `summary.txt` and raw logs/artifacts are retained alongside it.

## Failure behavior

Module load errors do not prevent process execution; they are recorded and the
scenario continues to collect evidence.  Process failures/timeouts similarly
collect output and events before teardown.  Any failed assertion, module load,
or requested module unload makes the final scenario result fail.

## Current limitations

- v1 accepts upstream Linux targets only, because Buildroot gives KLab a known
  SDK/rootfs pair for cross-architecture execution.
- one guest per scenario; multi-VM coordination is the next orchestration step.
- process commands are intentionally shell commands and scenarios are trusted
  test inputs, not an untrusted-code sandbox.
- live cross-architecture scenario validation requires QEMU on the user's host;
  this development environment does not provide the required system emulators.
