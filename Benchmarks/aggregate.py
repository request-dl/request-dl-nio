#!/usr/bin/env python3
#
# See LICENSE for this package's licensing information.
#
# Reads what run.sh wrote and prints, for each scenario, what the new version did against the old
# one: the mean of the ratio new/old, taken round by round, with a 95% interval. The first round
# is left out.

import argparse
import json
import math
import statistics
from collections import defaultdict

# Two-sided 95% Student t, by degrees of freedom; beyond the table, the normal's.
T95 = {1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228}


def interval(ratios):
    mean = statistics.mean(ratios)
    if len(ratios) < 2:
        return mean, float("nan")
    t = T95.get(len(ratios) - 1, 1.96)
    return mean, t * statistics.stdev(ratios) / math.sqrt(len(ratios))


def rate(result):
    # Bytes per second where a request carries a body worth the name, requests per second where
    # it does not.
    if result["scenario"] == "small":
        return result["requests"] / result["wallSeconds"]
    return result["bytes"] / result["wallSeconds"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results")
    parser.add_argument("--old", required=True)
    parser.add_argument("--new", required=True)
    arguments = parser.parse_args()

    rows = defaultdict(dict)  # (scenario, round) -> {version: result}

    with open(arguments.results) as file:
        for line in file:
            record = json.loads(line)
            if record["round"] == 1:
                continue
            result = record["result"]
            rows[(result["scenario"], record["round"])][record["version"]] = result

    scenarios = sorted({scenario for scenario, _ in rows})

    print(f"\n{arguments.new} against {arguments.old}, ratio new/old (95% interval), first round left out")
    print(f"{'scenario':10} {'rounds':>6} {'throughput':>22} {'cpu per request':>22}")

    for scenario in scenarios:
        throughput, cpu = [], []

        for (name, _), versions in sorted(rows.items()):
            if name != scenario or arguments.old not in versions or arguments.new not in versions:
                continue

            old, new = versions[arguments.old], versions[arguments.new]
            throughput.append(rate(new) / rate(old))
            cpu.append((new["cpuSeconds"] / new["requests"]) / (old["cpuSeconds"] / old["requests"]))

        if not throughput:
            continue

        t_mean, t_half = interval(throughput)
        c_mean, c_half = interval(cpu)

        t_text = f"{t_mean:.3f} ± {t_half:.3f}"
        c_text = f"{c_mean:.3f} ± {c_half:.3f}"
        print(f"{scenario:10} {len(throughput):>6} {t_text:>22} {c_text:>22}")


if __name__ == "__main__":
    main()
