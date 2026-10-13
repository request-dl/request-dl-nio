#!/bin/bash
# N6: a cache hit read from the disk tier.
#
# Reads a chunked body once to fill a disk cache, waits until the whole entry can be read, and times
# the second read, which is served from the cache (the result line says whether the server saw it).
# A revision that serves an entry while it is still being written would hand over a short one, so
# the probe waits for the full size before it starts the clock.
#
#   ./run-n6.sh <label=path/to/cache-probe> [...]
#
# Environment: SIZES (default "32 128", MiB), RUNS (default 5), PORT (default 18772).

set -u

SIZES=${SIZES:-"32 128"}
RUNS=${RUNS:-5}
PORT=${PORT:-18772}
HERE=$(cd "$(dirname "$0")" && pwd)

python3 "$HERE/chunked-server.py" "$PORT" &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 1

for size in $SIZES; do
  for entry in "$@"; do
    label=${entry%%=*}
    probe=${entry#*=}

    for executor in urlSession nio; do
      for run in $(seq 1 "$RUNS"); do
        echo "rev=$label executor=$executor run=$run $("$probe" replay "$PORT" "$executor" "$size")"
      done
    done
  done
done
