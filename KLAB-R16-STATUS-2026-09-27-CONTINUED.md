# KLab r16 status — 2026-09-27 continued

## Current checkpoint

r16 topology/fault orchestration has now completed the no-QEMU freeze-gate work for both link recovery and the first destructive-fault semantics. Live multi-VM behavior is still intentionally unclaimed until it is run on the KLab host with system QEMU.

## Changes in this continuation

### Edge-triggered action scheduling

- Actions are registered before process execution.
- `started` actions fire immediately after successful guest-agent spawn.
- A pending `ready` action now makes readiness an active scheduler obligation immediately after that process is spawned, even when no process dependency also waits on readiness.
- `ready` actions therefore cannot drift to the generic post-spawn action phase simply because another process did not consume the ready state.
- `exited` actions remain tied to an actually observed process wait result; an `EXPECTED_GUEST_LOSS` classification is not synthesized into a normal process-exited trigger.

### Link recovery freeze gate

- `link-flap-recovery-r16.json` triggers the client link flap at client `started`.
- The retrying client executes during the outage and must recover after the link comes back.
- The synthetic QMP test verifies both `set_link(..., false)` and `set_link(..., true)`.
- `tests/r16-freeze-gate.sh` validates the routed two-LAN topology, four interfaces, router forwarding/routes, link-fault metadata, QMP down/up sequence, and retry/recovery behavior.

### Destructive-fault hardening

- Added `guest-loss-results.tsv`; canonical report v2 now exposes it as `guest_losses`.
- Expected destructive loss is classified explicitly rather than being inferred only from missing guest RPCs.
- A destructive action with `expected: false` records `UNEXPECTED` guest loss and increments scenario failures.
- `guest-power-cut` now requires a present, numeric, live session PID before SIGKILL and verifies that the host process actually disappears.
- `kernel-panic` records the console length before injection and accepts only a new panic signature after that point. Old panic markers cannot make the test pass.
- Panic action evidence records the guest-agent RPC return code because a real panic may sever the control channel before a reply.
- Signal action values are restricted to Linux 1..64.
- Destructive action `expected` must be boolean.

## Focused validation completed here

PASS:

- `tests/multiguest-r16-model.sh`
- `tests/multiguest-plan.sh`
- `tests/multiguest-dryrun.sh`
- `tests/r16-freeze-gate.sh`
- `tests/qmp-link-control.sh`
- `tests/r16-destructive-faults.sh`
- `tests/guest-agent-protocol.sh`
- `tests/guest-agent-gate.sh`
- `tests/network-profile-model.sh`
- `tests/scenario-plan.sh`
- `tests/scenario-report.sh`
- `tests/r16-overnight-resume.sh`
- shell syntax checks for touched scripts
- Python bytecode compilation for `lib/multiguest_plan.py`

`tests/r16-destructive-faults.sh` uses the real local `klab-agent` to validate readiness -> process-group SIGTERM -> expected signal result, plus stale-vs-fresh panic evidence semantics.

## Validation boundary

This development environment still does not provide `qemu-system-*`. Therefore these are **not yet live-proven** here:

- packet forwarding across the two-LAN QEMU topology,
- guest-visible link down/up and recovery,
- hard QEMU power cut of a live KLab guest,
- SysRq panic of a live KLab guest,
- mixed-architecture routed traffic.

## Next host-side gate

Run the non-destructive cases first:

```bash
./kernel-lab.sh multiguest-run examples/multiguest/two-lan-router-r16.json
./kernel-lab.sh multiguest-run examples/multiguest/link-flap-recovery-r16.json
```

Review `report.json`, `summary.txt`, `action-results.tsv`, the per-interface PCAPs, and the merged timeline. If both pass, run the process-signal and guest-power-cut cases:

```bash
./kernel-lab.sh multiguest-run examples/multiguest/process-failure-r16.json
./kernel-lab.sh multiguest-run examples/multiguest/guest-power-cut-r16.json
```

Review `guest-loss-results.tsv` / `guest_losses` for the power-cut case. Only then enable the destructive panic case:

```bash
./kernel-lab.sh multiguest-run examples/multiguest/kernel-panic-r16.json
```

After those are clean, the next feature step is the mixed-architecture routed scenario and then folding all of them into the resumable r16 overnight matrix.

## Live host closure — 2026-10-17

The prior no-QEMU validation boundary is closed on this host. Routed two-LAN traffic, QMP link recovery, coordinated signal delivery, expected QEMU power loss, fresh SysRq panic evidence, and mixed x86_64/AArch64/i386 routed traffic all passed. See `KLAB-R16-LIVE-QEMU-VALIDATION.md`.
