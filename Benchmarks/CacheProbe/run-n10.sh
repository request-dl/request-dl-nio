#!/bin/bash
# N10: a cancelled image load stops its download.
#
# A fast-scrolled list starts a load for every row that comes into view and cancels it when the row
# goes out of view. This starts LOADS loads of an image of IMAGE_MIB, one every INTERVAL ms,
# cancels each CANCEL_AFTER ms after it started, and asks the server how many bytes it handed to
# the connections. A cancelled load that does not stop its download keeps taking bandwidth until
# the whole image is there.
#
#   ./run-n10.sh <label=path/to/cache-probe> [...]
#
# Environment: LOADS (default 40), IMAGE_MIB (default 10), CANCEL_AFTER (default 100), INTERVAL
# (default 20), SETTLE (default 3000), RUNS (default 3), PORT (default 18774).

set -u

LOADS=${LOADS:-40}
IMAGE_MIB=${IMAGE_MIB:-10}
CANCEL_AFTER=${CANCEL_AFTER:-100}
INTERVAL=${INTERVAL:-20}
SETTLE=${SETTLE:-3000}
RUNS=${RUNS:-3}
PORT=${PORT:-18774}
HERE=$(cd "$(dirname "$0")" && pwd)

python3 "$HERE/chunked-server.py" "$PORT" &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 1

for entry in "$@"; do
  label=${entry%%=*}
  probe=${entry#*=}

  for executor in urlSession nio; do
    for run in $(seq 1 "$RUNS"); do
      echo "rev=$label executor=$executor run=$run" \
        "$("$probe" images "$PORT" "$executor" "$LOADS" "$IMAGE_MIB" "$CANCEL_AFTER" "$INTERVAL" "$SETTLE")"
    done
  done
done
