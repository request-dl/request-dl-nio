#!/usr/bin/env python3
#
# See LICENSE for this package's licensing information.
#
# Runs `memory-probe` builds against the same local server, scenario after scenario and round after
# round, with the order of the builds alternating so that neither always gets the quieter half, and
# prints the median of each metric, with the ratio to the first build. The first round is thrown
# away. What it ran is in `results-*.jsonl`.
#
#     ./run.py before=path/to/memory-probe after=path/to/memory-probe [--rounds 5] [--scale 1] [--port 18931]
#
# `--scale` shrinks the sizes and the counts (0.05 is enough to see that it all runs); the numbers
# worth reading are the ones at 1, on a machine doing nothing else. Needs `python3` and nothing else.

import argparse
import json
import os
import re
import statistics
import subprocess
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument("builds", nargs="+", help='"label=path/to/memory-probe", the first one is the reference')
parser.add_argument("--rounds", type=int, default=5)
parser.add_argument("--scale", type=float, default=1.0)
parser.add_argument("--port", default="18931")
options = parser.parse_args()

builds = []
for argument in options.builds:
    label, _, path = argument.partition("=")
    if not path or not os.path.exists(path):
        sys.exit(f"not a build: {argument}")
    builds.append((label, path))

here = os.path.dirname(os.path.abspath(__file__))
port = options.port


def scaled(value, minimum=1):
    return str(max(minimum, int(value * options.scale)))


scenarios = []
for executor in ("nio", "urlSession"):
    scenarios += [
        (f"download-data/{executor}", ["download", port, executor, scaled(256), "data"]),
        (f"download-stream/{executor}", ["download", port, executor, scaled(256), "stream"]),
        (f"upload/{executor}", ["upload", port, executor, scaled(128)]),
        (f"small/{executor}", ["small", port, executor, scaled(4000, 20), "16"]),
    ]
scenarios.append(("redirect/nio", ["redirect", port, "nio", scaled(600, 20)]))


def parse(line):
    return {key: value for key, value in re.findall(r"(\w+)=(\S+)", line)}


server = subprocess.Popen([sys.executable, os.path.join(here, "server.py"), port])
time.sleep(1.0)

rows = []
out_path = os.path.join(here, time.strftime("results-%Y%m%d-%H%M%S.jsonl"))

try:
    with open(out_path, "w") as out:
        for round_number in range(1, options.rounds + 1):
            order = builds if round_number % 2 else list(reversed(builds))

            for label, args in scenarios:
                for build_label, path in order:
                    run = subprocess.run([path, *args], capture_output=True, text=True, timeout=900)
                    lines = [line for line in run.stdout.splitlines() if line.startswith("RESULT")]

                    if run.returncode != 0 or not lines:
                        print(f"FAILED {build_label} {label}: rc={run.returncode} {run.stderr[-300:]}", flush=True)
                        continue

                    row = {"round": round_number, "build": build_label, "scenario": label, **parse(lines[0])}

                    if len(lines) > 1:
                        row["settled"] = parse(lines[1])

                    rows.append(row)
                    out.write(json.dumps(row) + "\n")
                    print(f"round {round_number} {build_label:8} {label}: {lines[0][7:]}", flush=True)
finally:
    server.kill()

reference = builds[0][0]


def median(selected, key, settled=False):
    values = [float((row["settled"] if settled else row)[key]) for row in selected if (not settled or "settled" in row)]
    return statistics.median(values) if values else float("nan")


print(f"\nmedian of rounds 2..{options.rounds}, ratio to {reference}; what ran is in {out_path}")
print(f"{'scenario':26} {'metric':18}" + "".join(f"{label:>12}" for label, _ in builds) + "   ratios")

for label, _ in scenarios:
    selected = {
        build: [row for row in rows if row["scenario"] == label and row["build"] == build and row["round"] > 1]
        for build, _ in builds
    }

    if not all(selected.values()):
        continue

    metrics = [("seconds", False), ("cpu", False), ("grew_mib", False), ("peak_mib", False), ("threads", False)]

    if label.startswith("redirect"):
        metrics += [("after_mib", True), ("threads", True)]

    for metric, settled in metrics:
        values = [median(selected[build], metric, settled) for build, _ in builds]
        ratios = " ".join(f"{value / values[0]:.2f}" if values[0] else "nan" for value in values[1:])
        name = f"settled_{metric}" if settled else metric
        print(f"{label:26} {name:18}" + "".join(f"{value:12.2f}" for value in values) + f"   {ratios}")
