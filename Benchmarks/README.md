# Benchmarks

Measures what the metrics of the `async-http-client` fork cost, by running the same client against two versions of it: one without them (1.38.2) and one with them (1.39.1 and later).

This is a package of its own and nothing builds it but you: it is not part of the library's manifest, and CI does not run it. It does not depend on RequestDL either. The fork is pinned to one exact version per build (`BENCH_AHC_VERSION`), which a dependency on RequestDL, that needs it `from: "1.39.1"`, would not allow.

## Running it

It runs on macOS and on Linux. The summary at the end needs `python3`; without it, everything still runs and what it measured is in `results-*.jsonl`, which `aggregate.py` can summarise wherever there is one. (The `swift:6.2` image has no `python3`, so inside a container the summary is the part to do outside.)

```bash
cd Benchmarks
./run.sh                       # the real thing: 6 rounds, full sizes
./run.sh --rounds 3 --scale 0.01   # a quick check that it all runs
```

It builds the client against each version, starts `bench-server` in a process of its own, runs every scenario against both versions, round after round, with the order alternating so neither one always gets the quieter half, and prints the ratio new/old of each scenario with a 95% interval. The first round is left out. What it ran is in `results-*.jsonl`.

| Scenario | What it does |
| --- | --- |
| `download` | 16 downloads of 256 MiB at once. |
| `upload` | 8 uploads of 128 MiB at once, from buffers of 64 KiB. |
| `small` | 60 000 small `GET`s, 32 at a time. |

It reports throughput (bytes per second, requests per second for `small`) and the CPU the process spent per request, `user + system`.

## Reading it

Run it on a machine doing nothing else, and more than once: on small requests the run-to-run noise has been 15-20%, which is as large as the effect being looked for. A ratio whose interval contains 1 says nothing was detected, not that nothing is there.

What was seen before, when the harness lived in a temporary directory: no detectable cost on bulk transfers (download 1.039 ± 0.060, upload 0.979 ± 0.038 in throughput, new/old, 95% interval), and for 60 000 small requests about 5-10% more CPU per request against 15-20% of noise, which settled nothing. That was on Linux only.
