# R23 live validation

The offline audit is ready to transition to live testing. Run from the extracted KLab directory as a normal user:

```sh
./live-validation-ubuntu1704.sh
```

The script uses `./klab-live-ubuntu1704/` by default for an isolated staging home, transfer directory, offline home, and log. Override with `KLAB_LIVE_BASE=/path ./live-validation-ubuntu1704.sh`.

A pass requires all static regressions, staging doctor, exact Ubuntu 17.04 preparation with `--distro-toolchain`, verification of generated shared artifacts and thin target, fresh offline import, and the built-in QEMU smoke/module-load test to succeed. Do not run KLab itself with sudo.

The first failure is useful evidence. Preserve `klab-live-ubuntu1704/live-validation.log` and the transfer directory if the script stops.
