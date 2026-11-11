# KLab r16 mixed-architecture routed checkpoint

## Implemented
- Canonical mixed routed path: x86_64 client -> aarch64 router -> i386 server.
- Two isolated LANs, endpoint static routes, and IPv4 forwarding on the two-NIC aarch64 router.
- Client waits on the i386 server's READY state before attempting routed traffic.
- Regression test locks guest architectures and architecture-specific QEMU/NIC model data.
- Existing r16 overnight matrix already runs routed-mixed-arch by default and checks each guest's required QEMU binary.

## Validation completed
PASS: `lib/multiguest_plan.py validate examples/multiguest/routed-mixed-arch-r16.json`
PASS: `tests/r16-mixed-arch-routed.sh`
PASS: architecture model profiles for x86_64, aarch64, and i386 were individually resolved.
PASS: r16 overnight mixed-case wiring is present.

## Validation boundary
No live QEMU traffic is claimed here. Host validation still requires the three system-QEMU binaries and prepared x86_64 v5.15, aarch64 v6.6, and i386 v5.10 targets/userspaces.

## Host gate
`./kernel-lab.sh multiguest-run examples/multiguest/routed-mixed-arch-r16.json`

Inspect `report.json`, `summary.txt`, per-interface PCAPs, and the merged timeline. Success means the x86_64 client payload traverses both LANs through the aarch64 forwarding guest and reaches the i386 server with all process expectations satisfied.
