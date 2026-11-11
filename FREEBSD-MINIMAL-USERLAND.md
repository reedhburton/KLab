# FreeBSD minimal-userland gate

KLab uses the official FreeBSD release image as both the full userland and the minimum supported FreeBSD execution environment. This is an intentional alternate gate, not a missing artifact.

A Linux-style BusyBox root is not a valid FreeBSD compatibility test. FreeBSD kernel modules are release-ABI coupled to the matching kernel and `/boot/kernel`; module loading, the runtime linker, base utilities, device setup, and `rc` services all come from the matching FreeBSD base system. Replacing that base with an unrelated small root would stop testing the target represented by the `.klab` bundle.

The minimal FreeBSD profile is therefore the matching release image with only the services required by the test enabled. The release gate requires the exact target to boot, configure `vtnet0`, build/load/unload its module test, run the native process and exec probes, start the base-system `sshd`, and complete a real key-authenticated command. Network isolation remains enforced by QEMU `restrict=on`; ARM64 container transport uses a container-local TCP relay and exposes only the requested host SSH port.

This alternate gate applies only to FreeBSD. Linux continues to require separate minimal and full userlands.
