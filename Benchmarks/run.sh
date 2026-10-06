#!/bin/bash
#
# See LICENSE for this package's licensing information.
#
# Compares the async-http-client fork at two versions, with the same client code and the same
# server: builds the client against each, starts the server in a process of its own, and runs
# every scenario against both, interleaved, round after round. The first round is thrown away.
#
#     ./run.sh [--rounds 6] [--scale 1] [--old 1.38.2] [--new 1.39.1] [--port 18080]
#
# `--scale` shrinks the sizes and the counts (0.01 is enough to see that it all runs); the numbers
# worth reading are the ones at 1, on a machine doing nothing else.

set -euo pipefail

ROUNDS=6
SCALE=1
OLD=1.38.2
NEW=1.39.1
PORT=18080

while [ $# -gt 0 ]; do
    case "$1" in
        --rounds) ROUNDS="$2"; shift 2 ;;
        --scale) SCALE="$2"; shift 2 ;;
        --old) OLD="$2"; shift 2 ;;
        --new) NEW="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

cd "$(dirname "$0")"

OUT="results-$(date +%Y%m%d-%H%M%S).jsonl"

for version in "$OLD" "$NEW"; do
    BENCH_AHC_VERSION="$version" swift build -c release --scratch-path ".build-$version" --product bench-client
done

BENCH_AHC_VERSION="$NEW" swift build -c release --scratch-path ".build-$NEW" --product bench-server

".build-$NEW/release/bench-server" "$PORT" > /dev/null &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 100); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
        break
    fi

    sleep 0.1
done

for round in $(seq 1 "$ROUNDS"); do
    # Which one goes first alternates, so neither gets the quieter half of a round.
    if [ $((round % 2)) -eq 1 ]; then
        ORDER="$OLD $NEW"
    else
        ORDER="$NEW $OLD"
    fi

    for scenario in download upload small; do
        for version in $ORDER; do
            line=$(".build-$version/release/bench-client" --server "http://127.0.0.1:$PORT" --scenario "$scenario" --scale "$SCALE")
            echo "{\"round\":$round,\"version\":\"$version\",\"result\":$line}" >> "$OUT"
            echo "round $round $scenario $version: $line"
        done
    done
done

if command -v python3 > /dev/null; then
    python3 aggregate.py "$OUT" --old "$OLD" --new "$NEW"
else
    echo "python3 not found: what ran is in $OUT, and aggregate.py can summarise it where there is one."
fi
