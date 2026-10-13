#!/bin/bash
# P3: the threads of a process that touches the disk cache, in the build without NIO.
#
# Without the `NIOTransport` trait the file system calls run on a pool of threads the package keeps
# itself. This counts the threads of a process that writes and reads a few entries. Build the probe
# with `CACHE_PROBE_TRAITS=none` (see README.md), one build per revision.
#
#   ./run-p3.sh <label=path/to/cache-probe> [...]
#
# Environment: ENTRIES (default "5 200"), RUNS (default 3).

set -u

ENTRIES=${ENTRIES:-"5 200"}
RUNS=${RUNS:-3}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for entries in $ENTRIES; do
  for entry in "$@"; do
    label=${entry%%=*}
    probe=${entry#*=}

    for run in $(seq 1 "$RUNS"); do
      directory="$WORK/$label-$entries-$run"
      echo "rev=$label entries=$entries run=$run $("$probe" files "$directory" "$entries")"
      rm -rf "$directory"
    done
  done
done
