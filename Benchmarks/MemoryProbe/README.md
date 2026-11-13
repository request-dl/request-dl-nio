# MemoryProbe

Measures what the client costs in time, CPU, memory and threads, through the public API of RequestDL, so the same binary can be built against any revision of the package and the numbers compared. It is a package of its own and, like `CacheProbe`, it does depend on RequestDL. Nothing builds it but you; CI does not.

## Building it

It measures the checkout it lives in:

```bash
cd Benchmarks/MemoryProbe
swift build -c release
```

To compare revisions, export each one and point `MEMORY_PROBE_REV` at it, with a build directory of its own:

```bash
git archive --format=tar -o /tmp/before.tar <sha> && mkdir /tmp/before && tar -xf /tmp/before.tar -C /tmp/before
MEMORY_PROBE_REV=/tmp/before swift build -c release --scratch-path /tmp/build-before
```

SwiftPM names a path dependency after its directory, so give the exports different names.

## Running it

`run.py` starts `server.py` (a small local HTTP server, in a process of its own), runs every scenario against each build, round after round, with the order of the builds alternating, and prints the median of each metric with the ratio to the first build. The first round is left out. It needs `python3` and nothing else.

```bash
python3 run.py before=/tmp/build-before/release/memory-probe after=.build/release/memory-probe
python3 run.py before=... after=... --rounds 3 --scale 0.05   # a quick check that it all runs
```

What ran is in `results-*.jsonl`.

| Scenario | What it does |
| --- | --- |
| `download-data` | One download of 256 MiB through `DataTask`, which keeps the body. |
| `download-stream` | One download of 256 MiB through `DownloadTask`, read piece by piece. |
| `upload` | One upload of 128 MiB. |
| `small` | 4 000 small `GET`s, 16 at a time. |
| `redirect` | 600 sequential `GET`s under a redirect strategy, then the memory and threads again after 3 seconds. |

Each runs on `nio` and on `urlSession`, except `redirect`, which is `nio` only. For each it reports the seconds, the CPU (`user + system`) the process spent, the resident memory it grew by and its peak, and the threads it had at the end. The result line says which executor ran: without NIO there is no other than `urlSession`.

## Reading it

Run it on a machine doing nothing else, and more than once. Medians over a few rounds hide noise: look at the spread of the rounds in `results-*.jsonl` before trusting a ratio, since two builds whose ranges overlap have not been told apart.

The resident memory is read from the process, so it is the high water mark of what was live, not what the allocator gives back. In `download-data` it cannot go below the size of the body, which the result itself holds: that scenario is about time and CPU, and the pieces of a stream (`download-stream`) are where memory shows.

What was seen when it was first run, on a Mac with Apple silicon, in release, over the loopback (4 rounds after the first, medians): the change from `DataTask` receiving the body untouched instead of re-chunking it was a download of 256 MiB in 0.09 s instead of 3.6 s on `nio`; a redirect strategy that no longer leaves a client behind took the process from 11.5 threads to 6.5 after 600 requests; and the peak resident memory of a stream, upload and small requests did not change beyond the noise. That was on macOS only.
