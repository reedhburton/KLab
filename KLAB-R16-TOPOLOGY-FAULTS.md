# KLab r16 checkpoint — topology/fault orchestration

## Result

r16 completes the first topology/fault layer on top of r15 multi-guest execution.

Implemented:

- multiple named LANs per scenario
- multiple NICs per guest
- privilege-free QEMU multicast Ethernet buses
- router guests and static routes
- per-link QEMU device identities
- PCAP capture and fixed link delay
- QMP link flap/recovery
- readiness markers and dependency graph ordering
- dependency failure policy (`skip`, `run`, `fail`)
- process signal injection
- hard guest power-loss injection
- opt-in kernel panic injection
- expected destructive-guest-loss semantics
- report schema v2 with topology/actions/artifacts/timeline
- resumable r16 overnight fault matrix

## Important hardening in this checkpoint

1. Persistent session socket/QMP identity already includes the session name, allowing identical kernel targets to run simultaneously.
2. Route gateways are now planner-validated as directly reachable from one of the guest's interfaces.
3. Interface/network delays and link-flap durations reject negative values.
4. Upstream E2E kernels force `CONFIG_MAGIC_SYSRQ` and `CONFIG_PROC_SYSCTL` so the panic path is reproducible.
5. Exit-dependent processes no longer blindly start after a failed prerequisite; the scenario selects skip/run/fail behavior.
6. Gate orchestration ignores dependency-skipped processes, preventing a skipped participant from hanging a cross-guest gate.

## Host validation still required

This environment does not provide `qemu-system-*`. The first host run should therefore focus on the two simplest live cases before enabling destructive faults:

```bash
./kernel-lab.sh multiguest-run examples/multiguest/two-lan-router-r16.json
./kernel-lab.sh multiguest-run examples/multiguest/link-flap-recovery-r16.json
```

If those pass, run:

```bash
./klab-fault-overnight-r16.sh
```

Keep kernel panic disabled initially. Enable it only after normal routing/link fault results are reviewed:

```bash
KLAB_R16_ENABLE_PANIC=1 ./klab-fault-overnight-r16.sh
```

## Compatibility validation

Focused PASS results include:

- `tests/multiguest-r16-model.sh`
- `tests/qmp-link-control.sh`
- `tests/multiguest-plan.sh`
- `tests/multiguest-dryrun.sh`
- `tests/guest-agent-gate.sh`
- `tests/guest-agent-protocol.sh`
- `tests/network-profile-model.sh`
- `tests/scenario-plan.sh`
- `tests/scenario-report.sh`
- `tests/r16-overnight-resume.sh`
- `tests/provider-contract.sh`
- `tests/toolchain-boundary.sh`
- `tests/wide-sweep-regressions.sh`
- shell syntax checks
- Python compilation checks

No live QEMU success is claimed by this checkpoint.
