# R27 live-validation fix

Ubuntu 17.04 exposed that `/usr/bin/awk` is an alternatives-managed symlink. `dpkg-query -S /usr/bin/awk` need not report an owning package even though the final executable (normally mawk) is package-owned. Buildenv capture now resolves each baseline tool to its final executable before querying package ownership and records that resolved executable in `host-tool-owners.tsv`. Runtime ownership re-proof already queries the recorded resolved path, so capture and execution now use the same semantic object.

This preserves the fail-closed ownership contract; it does not exempt alternatives-managed tools from provenance.
