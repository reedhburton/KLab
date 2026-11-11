# Ubuntu generic kernel catalog and queue

KLab can inventory exact generic kernel ABI packages exposed by the supported Ubuntu series repositories and compare them with the local offline warehouse:

```sh
KLAB_ROOT=/path/to/klab-root \
  ./tools/ubuntu-kernel-catalog.sh /path/to/offline-repo/ubuntu-generic.tsv
```

The catalog covers releases 16.04, 18.04, 20.04, 22.04, 24.04, and 26.04 by default. Override `KLAB_UBUNTU_CATALOG_RELEASES` with a space-separated release list. A point-release label is not a stable package boundary: Ubuntu publishes kernel ABIs through the series repository, so the catalog records each exact installable ABI instead.

Acquire missing targets and validate them with their matching native userspace using the resumable bounded queue:

```sh
KLAB_ROOT=/path/to/klab-root \
KLAB_QUEUE_FREE_GIB=20 \
KLAB_QUEUE_LIMIT=5 \
  ./klab-ubuntu-generic-queue.sh /path/to/offline-repo/ubuntu-generic.tsv \
  /path/to/offline-repo/ubuntu-queue-run
```

The queue retains every result in `status.tsv`, never overwrites an earlier result, and stops before crossing the configured free-space floor. A PASS proves exact `uname -r`, matching Ubuntu userspace identity, working boot, and working guest command transport. It does not claim that kernel packages removed from current repositories have been tested; those require a historical snapshot or separately retained package archive.
