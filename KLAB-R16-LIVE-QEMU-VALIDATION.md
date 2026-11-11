# KLab r16 live QEMU validation — 2026-10-17

All required live topology and fault scenarios passed on the local KLab host with system QEMU. Evidence is stored under `library/v1-live-qemu-2026-10-17` outside the release source tree.

| Scenario | Result | Evidence |
|---|---|---|
| Routed two-LAN topology | PASS | Three x86_64 V6.6 guests; endpoint traffic crossed the forwarding router |
| Link flap and recovery | PASS | Client QMP link down for 800 ms; restored in 913 ms total; retrying traffic completed |
| Coordinated process failure | PASS | Ready-triggered SIGTERM delivered in 78 ms; expected signal 15 observed |
| Guest power cut | PASS | Live victim QEMU PID killed and verified absent; loss classified EXPECTED |
| Kernel panic | PASS | Fresh `Kernel panic - not syncing: sysrq triggered crash` after injection; expected loss recorded |
| Mixed-architecture routing | PASS | V5.15 x86_64 client through V6.6 AArch64 router to V5.10 i386 server, with four nonempty PCAPs |

The first live panic attempt found a nounset bug in the fresh-panic evidence helper: Bash expanded an arithmetic initializer before the same `local` declaration had bound its input. The helper now binds the offset separately and is exercised directly under nounset. Successful finalization also removes transient `error-context.txt` written by the expected panic control-channel break. Attempt 2 passed.
