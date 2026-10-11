# CacheProbe

Measures the response cache through the public API of RequestDL, so the same binary can be built against any revision of the package and the numbers compared. It is a package of its own, and unlike `Benchmarks` it does depend on RequestDL. Nothing builds it but you; CI does not.

## Building it

It measures the checkout it lives in:

```bash
cd Benchmarks/CacheProbe
swift build -c release
```

To compare revisions, export each one and point `CACHE_PROBE_REV` at it, with a build directory of its own:

```bash
git archive --format=tar -o /tmp/before.tar <sha> && mkdir /tmp/before && tar -xf /tmp/before.tar -C /tmp/before
CACHE_PROBE_REV=/tmp/before swift build -c release --scratch-path /tmp/build-before
```

SwiftPM names a path dependency after its directory, so give the exports different names.

## What it measures

Each script takes `label=path/to/cache-probe` arguments, one per build, and prints one line per run.

| Script | Question | Needs |
| --- | --- | --- |
| `run-n7.sh` | What a lookup of a key that is not there costs, in a disk cache of N entries. | Nothing. |
| `run-n15.sh` | The hit rate of a memory tier that is smaller than the set of keys, under a skewed access. | Nothing. |
| `run-n5.sh` | How much resident memory a chunked body larger than the memory tier takes, on each executor. | `python3`, for `chunked-server.py`. |

`run-n5.sh` runs each build with the cache off and with an 8 MiB memory tier. A revision that holds the whole body in the tier (the one before the fix) is the positive control: it shows the cache is engaged in the setup. The resident size is read from the process, so it is the high water mark of what was live, not what the allocator gives back.

## Reading it

Run it on a machine doing nothing else. The numbers it was first run with were taken on Apple silicon with a local SSD, a release build and a warm page cache; a spinning disk or a network file system will move the first two.
