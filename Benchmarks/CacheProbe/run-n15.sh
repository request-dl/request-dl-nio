#!/bin/bash
# N15: hit rate of a memory tier with room for about 100 entries, under a skewed access.
#
# The sequence of keys is fixed, so a rerun gives the same numbers. With an exponent of 0 the access
# is uniform and the hit rate is the share of the keys that fit; the gain of evicting the least
# recently used entry over the oldest one only shows when some keys are asked for more than others.
#
#   ./run-n15.sh <label=path/to/cache-probe> [...]
#
# Environment: ENTRIES (default 100), KEYS (default 1000), REQUESTS (default 20000),
# EXPONENTS (default "0 0.8 1.0 1.2").

set -u

ENTRIES=${ENTRIES:-100}
KEYS=${KEYS:-1000}
REQUESTS=${REQUESTS:-20000}
EXPONENTS=${EXPONENTS:-"0 0.8 1.0 1.2"}

for exponent in $EXPONENTS; do
  for entry in "$@"; do
    label=${entry%%=*}
    probe=${entry#*=}
    echo "zipf=$exponent rev=$label $("$probe" lru "$ENTRIES" "$KEYS" "$REQUESTS" "$exponent")"
  done
done
