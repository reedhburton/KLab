# KLab test suites

Suites live under `$KLAB_ROOT/suites/NAME`, so the normal KLab root remains the only working directory. Every suite uses the unified schema and can run once or across a target matrix. Create a suite template with:

```sh
klab suite create driver-matrix
```

Run it once with `klab suite run driver-matrix TARGET --arch ARCH`, or configure and queue multiple targets.

Edit `$KLAB_ROOT/suites/driver-matrix/suite.json` and select targets explicitly:

```json
{
  "schema": "klab-suite-v2",
  "name": "driver-matrix",
  "scenario": "scenario.json",
  "targets": [
    "upstream:v6.6@x86_64",
    {"target": "ubuntu:24.04", "arch": "aarch64"},
    "alpine:3.20@x86_64"
  ]
}
```

Then queue the entire matrix:

```sh
klab suite queue driver-matrix
```

Targets can also be selected without changing the manifest:

```sh
klab suite queue driver-matrix \
  --target upstream:v6.1@x86_64 \
  --target ubuntu:22.04@aarch64

klab suite queue driver-matrix --target-file targets.txt

# Add every target currently imported into this KLab root.
klab suite queue driver-matrix --all
```

A target file has one `TARGET@ARCH` per line; blank lines and lines beginning with `#` are ignored. `--output DIR` selects a stable result directory. Reuse that directory with `--resume` to skip targets that already have a PASS row. A failure does not stop later targets. `status.tsv` is the queue summary, while `scenarios/` contains the exact target-specific plans and `targets/` contains full reports.

Use `--dry-run` to validate and materialize the queue without booting guests:

```sh
klab suite queue driver-matrix --dry-run --output /tmp/driver-plan
```

## Artifacts

The referenced `scenario.json` uses the existing scenario artifact types:

- `modules[].source_dir` builds a kernel module against every selected target. The default `auto_load: true` loads it before processes start. Set `auto_load: false` to let a process load `/tmp/klab-modules/ID.ko` at the required point in the workflow.
- `builds[]` compiles a C userspace program separately with each target's captured SDK/toolchain and installs it at its `remote` path.
- `files[]` copies a precompiled program or data file unchanged into each guest and applies `mode`. This is appropriate when compatibility of one fixed binary is the subject of the test.

Example source build:

```json
{"id":"client", "source":"client.c", "remote":"/tmp/client", "static":true, "flags":["-O2"]}
```

Example precompiled input:

```json
{"source":"bin/my-tool", "remote":"/tmp/my-tool", "mode":"0755"}
```

KLab checks the architecture of artifacts it compiles. A precompiled file is intentionally used byte-for-byte; its process result proves whether that exact binary executes on the target.

## Ordered process workflows

A process may contain one `command`, as before, or an ordered `steps` array. `run` completes before the next step. `signal` publishes a named milestone. `wait_for` blocks until another process publishes that milestone. A final `exec` replaces the sequence controller, preserving its PID in the final program. `$KLAB_SEQUENCE_PID` exposes that original PID to commands.

```json
{
  "processes": [
    {
      "id": "module_owner",
      "steps": [
        {"run":"insmod /tmp/klab-modules/driver.ko", "signal":"module_ready"},
        {"run":"/tmp/configure-driver"},
        {"wait_for":"client_done"},
        {"exec":"/tmp/final-check --owner-pid $KLAB_SEQUENCE_PID"}
      ],
      "expected_exit": 0
    },
    {
      "id": "client",
      "steps": [
        {"wait_for":"module_ready"},
        {"run":"/tmp/client --exercise-device"},
        {"signal":"client_done"}
      ],
      "expected_exit": 0
    }
  ]
}
```

These are two OS processes. `module_owner` performs three ordered phases; its final executable inherits the original sequence PID. This is the precise way to express “a final command from the original PID.” Milestone waits use each process timeout and fail with exit 124 when ordering cannot be satisfied. Independent processes are still launched concurrently, so they can coordinate through milestones, barriers, sockets, files, or the tested kernel interface.

The generated report records normalized plans, target and architecture, compiled artifacts and hashes, module load state, every process exit status, stdout/stderr, guest events, and dmesg.

## Migrating an old local suite

Pre-release checkouts that created `klab-suite-v1` directories can convert them once with `klab suite migrate NAME`. KLab saves the old manifest as `suite.v1.json`, creates a unified scenario and manifest, and thereafter uses the same run and queue engine as every new suite. The runtime no longer accepts v1 directly.

## Multiple users and simultaneous queues

Multiple users can run queues at the same time. Give each user an independent writable KLab root and point all of them at the same read-only offline repository:

```sh
# Alice
KLAB_ROOT="$HOME/klab" KLAB_REPO=/srv/klab-offline \
  klab suite queue driver-matrix

# Bob, at the same time on the same host
KLAB_ROOT="$HOME/klab" KLAB_REPO=/srv/klab-offline \
  klab suite queue storage-tests
```

Each root owns its suites, build workspace, sessions, queue status, and reports. Generated queue IDs contain time, UID, PID, and a random component, so simultaneous submissions do not select the same result directory. The shared offline repository should be readable by the test users. Assign pulls, repository indexing, pruning, and volume changes to one repository-maintainer account rather than mutating that store from concurrent test jobs.

Do not configure several users to write the same `KLAB_ROOT`. KLab intentionally uses ordinary Unix ownership and per-user roots instead of making its session controls, credentials, and mutable workspaces globally writable. The operating system or a CI scheduler can impose CPU, memory, and QEMU concurrency limits independently.
