#!/bin/bash
# N8: uploads compressed with gzip, small and large, one and many at once.
#
# Compressing a body takes a thread of its own for the length of the upload. This times the uploads
# and counts the threads the process had at most while they ran.
#
#   ./run-n8.sh <label=path/to/cache-probe> [...]
#
# Environment: SHAPES (default "1x1 1x1024 100x1 100x1024", uploads x KiB), RUNS (default 3),
# PORT (default 18773).

set -u

SHAPES=${SHAPES:-"1x1 1x1024 100x1 100x1024"}
RUNS=${RUNS:-3}
PORT=${PORT:-18773}
HERE=$(cd "$(dirname "$0")" && pwd)

python3 "$HERE/chunked-server.py" "$PORT" &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 1

for entry in "$@"; do
  label=${entry%%=*}
  probe=${entry#*=}

  for executor in nio urlSession; do
    for shape in $SHAPES; do
      uploads=${shape%%x*}
      kibibytes=${shape##*x}

      for run in $(seq 1 "$RUNS"); do
        echo "rev=$label executor=$executor run=$run" \
          "$("$probe" compress "$PORT" "$executor" "$uploads" "$kibibytes")"
      done
    done
  done
done
