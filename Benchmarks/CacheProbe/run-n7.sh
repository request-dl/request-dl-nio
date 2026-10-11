#!/bin/bash
# N7: lookups of keys that are not in a disk cache of N entries, in a fresh process each time.
#
# A miss used to list the directory and stat every entry; now a miss does not scan again when the
# last scan was less than a second ago. All the lookups of a run come within that second, so what
# is seen is the cost of one scan against one scan per miss.
#
#   ./run-n7.sh <label=path/to/cache-probe> [...]
#
# Environment: ENTRIES (default "100 1000 5000"), MISSES (default 200), RUNS (default 5).

set -u

ENTRIES=${ENTRIES:-"100 1000 5000"}
MISSES=${MISSES:-200}
RUNS=${RUNS:-5}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for n in $ENTRIES; do
  for entry in "$@"; do
    label=${entry%%=*}
    probe=${entry#*=}
    directory="$WORK/$label-$n"

    echo "entries=$n rev=$label populate: $("$probe" populate "$directory" "$n")"

    for run in $(seq 1 "$RUNS"); do
      echo "entries=$n rev=$label run=$run $("$probe" miss "$directory" "$MISSES")"
    done

    rm -rf "$directory"
  done
done
