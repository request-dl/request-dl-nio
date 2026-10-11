#!/bin/bash
# N5: a chunked body larger than the memory tier must not be held by the cache.
#
# Reads a chunked body through a cache whose memory tier is 8 MiB and through no cache at all, and
# compares how much the resident memory of the process grew. The revision before the change is the
# positive control: if it grows by about the size of the body, the cache is engaged in this setup.
#
#   ./run-n5.sh <probe> [<probe> ...]       each argument is "label=path/to/cache-probe"
#
# Environment: BODY_MIB (default 500), RUNS (default 3), PORT (default 18765).

set -u

BODY_MIB=${BODY_MIB:-500}
RUNS=${RUNS:-3}
PORT=${PORT:-18765}
HERE=$(cd "$(dirname "$0")" && pwd)

python3 "$HERE/chunked-server.py" "$PORT" &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 1

for entry in "$@"; do
  label=${entry%%=*}
  probe=${entry#*=}

  for executor in urlSession nio; do
    for memory in 0 8; do
      for run in $(seq 1 "$RUNS"); do
        echo "rev=$label executor=$executor tier_mib=$memory body_mib=$BODY_MIB run=$run" \
          "$("$probe" chunked "$PORT" "$memory" "$executor" "$BODY_MIB")"
      done
    done
  done
done
