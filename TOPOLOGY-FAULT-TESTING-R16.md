# KLab r16 — topology and fault testing

r16 extends the r15 multi-guest runner from a single shared LAN into a declarative topology and fault-testing framework.

## Topology model

A scenario may declare multiple isolated IPv4 LANs. Each guest may have one or more named interfaces, and every interface has its own network, CIDR address, MAC address, guest interface name, QEMU device identity, optional PCAP capture, and optional transmit delay.

The host uses QEMU socket multicast backends for private, privilege-free Ethernet buses. No host TAP device or bridge is required. Router guests are ordinary KLab guests with two or more interfaces and `forward_ipv4: true`. Static routes are installed after boot. The planner rejects duplicate addresses/MACs, overlapping LAN definitions, and gateways that are not directly reachable from the declaring guest.

Per-link PCAP capture uses QEMU `filter-dump`. Fixed packet delay uses `filter-buffer`. Runtime link loss/recovery uses QMP `set_link` against the stable QEMU device id recorded for each interface.

## Process orchestration

Processes still run under the static `klab-agent`, but r16 adds readiness/dependency semantics on top of r14/r15 barriers and gates.

A process can publish readiness through a required stdout marker. Another process may depend on the first process reaching one of three states:

- `started`
- `ready`
- `exited`

Dependencies are validated as an acyclic graph before any VM is booted. Exit-based dependencies also have `on_dependency_failure` behavior:

- `skip` (default): do not start the dependent process if the prerequisite's asserted exit result failed.
- `run`: start the dependent process anyway and record that the prerequisite failure was ignored.
- `fail`: do not start the dependent process and record an additional dependency assertion failure.

Skipped processes are removed from guest/cross-guest gate participant sets so they cannot deadlock a gate.

## Fault actions

Actions run after process startup and may be triggered by another process reaching `started`, `ready`, or `exited`.

r16 provides:

- `link-flap`: set one QEMU NIC down, wait a controlled interval, then restore it.
- `signal`: signal a named guest process/process group through `klab-agent`.
- `guest-power-cut`: terminate a selected QEMU process without guest shutdown.
- `kernel-panic`: trigger SysRq crash inside a selected Linux guest and verify a panic marker appears in the console.

`CONFIG_MAGIC_SYSRQ` and `CONFIG_PROC_SYSCTL` are forced on for upstream E2E kernels so panic injection does not depend on a particular upstream defconfig.

Expected destructive guest loss is tracked separately. Processes and module cleanup on an intentionally destroyed guest are reported as `EXPECTED_GUEST_LOSS` rather than being misclassified as independent test failures.

## Reporting

The authoritative `klab-multiguest-report-v2` JSON includes:

- normalized scenario
- named LANs and interfaces
- target/kernel/architecture/session identity per guest
- process assertions and skip/failure state
- module load/unload results
- fault action results
- PCAP and other artifact hashes
- guest-agent events
- host orchestration/QMP events
- dmesg/console paths
- one merged timestamped timeline

The output directory remains useful after failure; teardown attempts to preserve console, PCAP, process output, module logs, and partial action results.

## Included scenarios

`examples/multiguest/two-lan-router-r16.json`
: Three x86_64 guests on two isolated LANs. A forwarding guest routes a client to a server.

`examples/multiguest/link-flap-recovery-r16.json`
: Routed client/server with PCAPs, fixed delay on one LAN, and a runtime client-link outage/recovery while the client retries TCP connection.

`examples/multiguest/process-failure-r16.json`
: Readiness-driven process signaling and expected signal assertion.

`examples/multiguest/guest-power-cut-r16.json`
: Host-side hard power loss of one guest after its workload becomes ready.

`examples/multiguest/kernel-panic-r16.json`
: Optional destructive kernel panic validation.

`examples/multiguest/routed-mixed-arch-r16.json`
: x86_64 server, x86_64 router, and aarch64 client on two routed LANs.

## Next-cycle runners

Run topology/fault scenarios only:

```bash
./klab-fault-overnight-r16.sh
```

Resume after interruption:

```bash
KLAB_R16_RESUME_RUN_ID=latest ./klab-fault-overnight-r16.sh
```

Kernel panic remains opt-in:

```bash
KLAB_R16_ENABLE_PANIC=1 ./klab-fault-overnight-r16.sh
```

The feature umbrella runs the earlier r15 coverage and then r16 fault/topology coverage:

```bash
./klab-feature-overnight-r16.sh
```

## Validation status

Validated without live QEMU in the build environment:

- topology/schema normalization
- duplicate/overlap/route-gateway validation
- dependency-cycle validation
- readiness/dependency planning
- guest-agent gate/barrier protocol
- multi-link boot argument construction/model checks
- QMP `set_link` request generation with a fake QMP server
- fault scenario dry runs
- overnight skip/resume behavior
- provider/toolchain/wide-sweep compatibility tests
- shell syntax and Python bytecode compilation

Live routed Ethernet, PCAP/filter behavior, and destructive guest/panic actions require the user's QEMU-equipped host and are intentionally not marked as validated yet.

## 2026-09-27 continuation: edge-triggered fault timing

The first r16 implementation registered fault actions correctly but executed them only after the process-spawn phase. That was deterministic, but it could move a short `after: started` or `after: ready` fault outside the intended window.

The runner now caches actions before process execution and observes process state transitions directly:

- `started` actions fire immediately after the guest agent confirms spawn.
- `ready` actions fire when the configured stdout readiness marker is observed.
- `exited` actions fire after the guest agent returns the final process result.
- If no other dependency observes a declared readiness/exit trigger, the action phase explicitly waits for that state so the action still runs.
- Action results now record trigger identity, start/completion timestamps, duration and detail in `action-results.tsv` and the canonical JSON report.

The link-flap recovery example now triggers the client NIC outage when the client process starts. The client intentionally waits briefly and retries connection while the link is down; success therefore requires QMP link restoration and subsequent data-path recovery rather than merely proving that a flap happened before the client ran.

`tests/r16-freeze-gate.sh` validates the two-LAN routed plan, link-fault metadata and trigger semantics, a complete synthetic QMP down/up sequence, and the retrying userspace client recovery behavior. Live multi-VM forwarding and guest-visible link behavior still require host-side QEMU validation.

## 2026-09-27 continuation: destructive-fault hardening

Ready-triggered actions now actively consume the readiness state immediately after the triggering process is spawned. This closes a scheduler gap where an action with `after.state = ready` could otherwise drift until the generic post-spawn action phase when no process dependency happened to observe readiness.

Destructive guest faults now produce `guest-loss-results.tsv`, which is folded into `report.json` as `guest_losses`. Each row records the guest, cause, action, whether the loss was expected by the scenario, classification, observation time, and evidence detail. An explicitly non-expected destructive loss is retained as guest-loss state but increments the scenario failure count.

`guest-power-cut` now requires the session PID to exist, be numeric, and refer to a currently running process before `SIGKILL` is attempted; an already-dead/stale PID is not accepted as a successful fault injection.

`kernel-panic` records the console byte offset immediately before SysRq injection and accepts only a panic signature appearing after that offset. A stale panic line from an earlier boot/crash therefore cannot satisfy the action. The guest-agent RPC return code is retained as evidence because a successful panic may tear down the control path before an RPC reply can complete.

Signal actions are planner-limited to the Linux signal range 1..64. `guest-power-cut` and `kernel-panic` require a boolean `expected` value (default `true`).

Synthetic validation is provided by `tests/r16-destructive-faults.sh`. It validates the destructive scenario models, uses the real local `klab-agent` to drive a readiness -> process-group SIGTERM -> expected signal result, verifies stale-vs-fresh panic evidence, and checks the runner's readiness-consumer and guest-loss-report wiring.
