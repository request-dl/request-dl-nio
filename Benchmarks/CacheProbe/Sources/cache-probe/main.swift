//
// See LICENSE for this package's licensing information.
//

import Foundation
import RequestDL

#if canImport(Darwin)
import Darwin
#endif

// Measurements of the cache that go through the public API only, so the same binary can be built
// against any revision of the package (see Package.swift). Each prints one line starting with
// `RESULT`.
//
//   populate <dir> <entries>
//       Writes small entries to the disk tier and waits until all of them are there.
//   miss <dir> <lookups>
//       Times lookups of keys that are not in the cache, in a process that has not seen it.
//   lru <entries> <keys> <requests> <zipf exponent>
//       Hit rate of a memory tier that holds about `entries` entries under a skewed access.
//   chunked <port> <memory MiB> <urlSession|nio|nts> <body MiB>
//       Reads a chunked body of that size from chunked-server.py through a cache whose memory
//       tier is that large (0 turns the cache off) and reports the resident memory it took.

let arguments = CommandLine.arguments
let entrySize = 1_024

func head(_ size: Int) -> ResponseHead {
    ResponseHead(
        url: URL(string: "https://example.com"),
        status: .init(code: 200, reason: "OK"),
        version: .init(minor: 1, major: 1),
        headers: HTTPHeaders([("Content-Length", String(size)), ("Cache-Control", "public, max-age=3600")]),
        isKeepAlive: true
    )
}

func entry(policy: DataCache.Policy.Set) async -> CachedData {
    await CachedData(
        response: head(entrySize),
        policy: policy,
        data: Data(repeating: 0x5A, count: entrySize)
    )
}

func recordCount(in directory: URL) -> Int {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        .filter { $0.hasSuffix(".cached") }
        .count
}

func nanoseconds(_ block: () async -> Void) async -> Double {
    let elapsed = await ContinuousClock().measure { await block() }
    return Double(elapsed.components.seconds) * 1e9 + Double(elapsed.components.attoseconds) / 1e9
}

func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
    sorted[min(sorted.count - 1, Int(Double(sorted.count) * fraction))]
}

/// The resident memory of this process right now, in bytes.
func residentBytes() -> Int {
    #if canImport(Darwin)
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

    let status = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }

    return status == KERN_SUCCESS ? Int(info.resident_size) : 0
    #else
    guard
        let statm = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8),
        let pages = statm.split(separator: " ").dropFirst().first.flatMap({ Int($0) })
    else { return 0 }

    return pages * Int(sysconf(Int32(_SC_PAGESIZE)))
    #endif
}

/// Keeps the highest resident size seen while it runs.
final class PeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak = residentBytes()
    private var task: Task<Void, Never>?

    func start() {
        task = Task.detached { [self] in
            while !Task.isCancelled {
                let current = residentBytes()
                lock.lock()
                peak = max(peak, current)
                lock.unlock()
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }

    func stop() -> Int {
        task?.cancel()
        lock.lock()
        defer { lock.unlock() }
        return max(peak, residentBytes())
    }
}

struct Xorshift {
    var state: UInt64

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 11) / Double(1 << 53)
    }
}

let mebibyte = 1_024 * 1_024

switch arguments[1] {
case "populate":
    let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
    let count = Int(arguments[3])!
    let cache = DataCache(memoryCapacity: 0, diskCapacity: 1 << 32, url: directory)

    for index in 0..<count {
        await cache.setCachedData(await entry(policy: .disk), forKey: "https://example.com/entry/\(index)")
    }

    var waited = 0

    while recordCount(in: directory) < count, waited < 1_200 {
        try? await Task.sleep(nanoseconds: 100_000_000)
        waited += 1
    }

    print("RESULT populated=\(recordCount(in: directory)) of \(count)")

case "miss":
    let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
    let count = Int(arguments[3])!
    let cache = DataCache(memoryCapacity: 0, diskCapacity: 1 << 32, url: directory)

    var times: [Double] = []
    var hits = 0

    for index in 0..<count {
        let time = await nanoseconds {
            if await cache.getCachedData(forKey: "https://example.com/new/\(index)", policy: .all) != nil {
                hits += 1
            }
        }

        times.append(time)
    }

    let sorted = times.sorted()
    let total = times.reduce(0, +)

    print(
        "RESULT first_ms=\(times[0] / 1e6) total_ms=\(total / 1e6) mean_ms=\(total / Double(count) / 1e6) "
            + "p50_ms=\(percentile(sorted, 0.5) / 1e6) p95_ms=\(percentile(sorted, 0.95) / 1e6) "
            + "max_ms=\(sorted.last! / 1e6) spurious_hits=\(hits)"
    )

case "lru":
    let entries = Int(arguments[2])!
    let keys = Int(arguments[3])!
    let requests = Int(arguments[4])!
    let exponent = Double(arguments[5])!

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cache-probe-\(UUID().uuidString)", isDirectory: true)

    let cache = DataCache(memoryCapacity: Int64(entries * entrySize), diskCapacity: 0, url: directory)

    var weights = (1...keys).map { 1 / pow(Double($0), exponent) }
    let norm = weights.reduce(0, +)
    var running = 0.0

    weights = weights.map {
        running += $0 / norm
        return running
    }

    var generator = Xorshift(state: 0x9E37_79B9_7F4A_7C15)
    var hits = 0
    var storedThenFound = 0

    for _ in 0..<requests {
        let draw = generator.next()
        let key = weights.firstIndex { $0 >= draw } ?? (keys - 1)
        let name = "https://example.com/k/\(key)"

        if await cache.getCachedData(forKey: name, policy: .memory) != nil {
            hits += 1
        } else {
            await cache.setCachedData(await entry(policy: .memory), forKey: name)

            if await cache.getCachedData(forKey: name, policy: .memory) != nil {
                storedThenFound += 1
            }
        }
    }

    print(
        "RESULT hit_rate=\(Double(hits) / Double(requests)) hits=\(hits) of \(requests) "
            + "stored_then_found=\(storedThenFound) misses=\(requests - hits)"
    )

case "chunked":
    let port = arguments[2]
    let memoryMebibytes = Int64(arguments[3])!
    let executor: Session.Executor =
        switch arguments[4] {
        case "nio": .nio
        case "nts": .nioTransportServices
        default: .urlSession
        }
    let bodyMebibytes = Int(arguments[5])!

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cache-probe-\(UUID().uuidString)", isDirectory: true)

    func makeTask(path: String) -> DownloadTask<some Property> {
        DownloadTask {
            if memoryMebibytes > 0 {
                Session()
                    .requiredExecutor(executor)
                    .cachePolicy(.memory)
                    .cacheStrategy(.returnCachedDataElseLoad)
                    .cache(memoryCapacity: memoryMebibytes * Int64(mebibyte), diskCapacity: 0, url: directory)
            } else {
                Session().requiredExecutor(executor)
            }

            BaseURL(.http, host: "127.0.0.1:\(port)")
            Path(path)
        }
    }

    // The first request puts the process in its steady state (connection, buffers), so what is
    // measured next is the body and not the start up.
    let warmUp = try await makeTask(path: "/big/1").result()

    for try await _ in warmUp.payload {}

    let before = residentBytes()
    let sampler = PeakSampler()
    sampler.start()

    let clock = ContinuousClock()
    var received = 0

    let elapsed = try await clock.measure {
        let result = try await makeTask(path: "/big/\(bodyMebibytes)").result()

        for try await chunk in result.payload {
            received += chunk.count
        }
    }

    let peak = sampler.stop()
    let after = residentBytes()

    func mebibytes(_ bytes: Int) -> String {
        String(format: "%.1f", Double(bytes) / Double(mebibyte))
    }

    print(
        "RESULT received_mib=\(received / mebibyte) before_mib=\(mebibytes(before)) "
            + "peak_mib=\(mebibytes(peak)) grew_mib=\(mebibytes(peak - before)) "
            + "after_mib=\(mebibytes(after)) seconds=\(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)"
    )

default:
    print("unknown mode \(arguments[1])")
}
