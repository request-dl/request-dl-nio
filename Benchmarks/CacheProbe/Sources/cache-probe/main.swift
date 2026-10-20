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
//   replay <port> <urlSession|nio|nts> <body MiB>
//       Reads a chunked body once to fill a disk cache, then reads it again from the cache and
//       times that second read. The server's request count says whether it came from the cache.
//   files <dir> <entries>
//       Writes and reads back small entries through the disk tier and reports the threads the
//       process has before, after and at most, which is the pool of the file system calls.
//   compress <port> <urlSession|nio|nts> <uploads> <KiB>
//       Sends that many uploads at once, each compressed with gzip, and reports the time and
//       the threads the process had at most.
//   images <port> <urlSession|nio|nts> <loads> <MiB> <cancel after ms> <interval ms> <settle ms>
//       A list scrolled fast: starts `loads` image loads one every `interval` ms, each of an image
//       of that many MiB that chunked-server.py sends at about 8 MiB a second, and cancels each
//       one `cancel after` ms after it started. After `settle` ms it reports how many bytes the
//       server handed to the connections.

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

/// The number of threads of this process right now.
func threadCount() -> Int {
    #if canImport(Darwin)
    var threads: thread_act_array_t?
    var count = mach_msg_type_number_t(0)

    guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else {
        return 0
    }

    vm_deallocate(
        mach_task_self_,
        vm_address_t(UInt(bitPattern: threads)),
        vm_size_t(Int(count) * MemoryLayout<thread_act_t>.size)
    )

    return Int(count)
    #else
    return (try? FileManager.default.contentsOfDirectory(atPath: "/proc/self/task").count) ?? 0
    #endif
}

/// Keeps the highest resident size and the most threads seen while it runs.
final class PeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak = residentBytes()
    private var peakThreadCount = threadCount()
    private var task: Task<Void, Never>?

    var peakThreads: Int {
        lock.withLock { max(peakThreadCount, threadCount()) }
    }

    func start() {
        task = Task.detached { [self] in
            while !Task.isCancelled {
                let current = residentBytes()
                let threads = threadCount()
                lock.withLock {
                    peak = max(peak, current)
                    peakThreadCount = max(peakThreadCount, threads)
                }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }

    func stop() -> Int {
        task?.cancel()
        return lock.withLock { max(peak, residentBytes()) }
    }
}

/// The executor a command line argument names. Without the `NIOTransport` trait there is no other
/// than `urlSession`, and the result line says which one was used.
func resolveExecutor(named name: String) -> Session.Executor {
    switch name {
    #if canImport(NIOCore)
    case "nio": return .nio
    case "nts": return .nioTransportServices
    #endif
    default: return .urlSession
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
    let executor = resolveExecutor(named: arguments[4])
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

case "replay":
    let port = arguments[2]
    let executor = resolveExecutor(named: arguments[3])
    let bodyMebibytes = Int(arguments[4])!

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("cache-probe-\(UUID().uuidString)", isDirectory: true)

    func makeTask(path: String) -> DownloadTask<some Property> {
        DownloadTask {
            Session()
                .requiredExecutor(executor)
                .cachePolicy(.disk)
                .cacheStrategy(.returnCachedDataElseLoad)
                .cache(memoryCapacity: 0, diskCapacity: Int64(bodyMebibytes * 4 * mebibyte), url: directory)

            BaseURL(.http, host: "127.0.0.1:\(port)")
            Path(path)
        }
    }

    func served() async throws -> Int {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/count")!)
        return Int(String(decoding: data, as: UTF8.self)) ?? -1
    }

    func read(_ path: String) async throws -> (bytes: Int, seconds: Double) {
        var bytes = 0

        let elapsed = try await ContinuousClock().measure {
            for try await chunk in try await makeTask(path: path).result().payload {
                bytes += chunk.count
            }
        }

        return (bytes, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
    }

    // The first read goes to the network and fills the disk tier.
    let path = "/big/\(bodyMebibytes)"
    let first = try await read(path)

    // A write to the cache is separate from the response, so wait until the whole entry can be
    // read. A revision that serves an entry while it is still being written (the one before the
    // fix) hands it over at once and short, which is why the size is checked and not just that
    // the entry exists.
    let key = "http://127.0.0.1:\(port)\(path)"
    let cache = DataCache(memoryCapacity: 0, diskCapacity: Int64(bodyMebibytes * 4 * mebibyte), url: directory)
    var waited = 0

    while waited < 600 {
        if let cached = await cache.getCachedData(forKey: key, policy: .disk),
            await cached.data.count >= bodyMebibytes * mebibyte
        {
            break
        }

        try? await Task.sleep(nanoseconds: 100_000_000)
        waited += 1
    }

    // The second one is what is measured.
    let before = try await served()
    let second = try await read(path)
    let after = try await served()

    print(
        "RESULT executor=\(executor) body_mib=\(bodyMebibytes) first_s=\(first.seconds) "
            + "second_s=\(second.seconds) second_mib_per_s=\(Double(second.bytes) / Double(mebibyte) / second.seconds) "
            + "second_bytes=\(second.bytes) from_cache=\(after == before) waited_ds=\(waited)"
    )

case "files":
    let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
    let count = Int(arguments[3])!

    let startThreads = threadCount()
    let sampler = PeakSampler()
    sampler.start()

    let cache = DataCache(memoryCapacity: 0, diskCapacity: 1 << 32, url: directory)

    for index in 0..<count {
        await cache.setCachedData(await entry(policy: .disk), forKey: "https://example.com/entry/\(index)")
    }

    var waited = 0

    while recordCount(in: directory) < count, waited < 600 {
        try? await Task.sleep(nanoseconds: 100_000_000)
        waited += 1
    }

    var found = 0

    for index in 0..<count {
        if await cache.getCachedData(forKey: "https://example.com/entry/\(index)", policy: .disk) != nil {
            found += 1
        }
    }

    let afterThreads = threadCount()
    _ = sampler.stop()

    print(
        "RESULT entries=\(count) found=\(found) threads_at_start=\(startThreads) "
            + "threads_after=\(afterThreads) threads_peak=\(sampler.peakThreads)"
    )

case "compress":
    let port = arguments[2]
    let executor = resolveExecutor(named: arguments[3])
    let uploads = Int(arguments[4])!
    let kibibytes = Int(arguments[5])!
    let body = Data((0..<kibibytes * 1_024).map { UInt8(truncatingIfNeeded: $0 % 251) })

    func upload() async throws {
        _ = try await UploadTask {
            Session().requiredExecutor(executor)
            BaseURL(.http, host: "127.0.0.1:\(port)")
            Path("/upload")
            RequestMethod(.put)
            Payload(data: body).compression(.gzip)
        }
        .collectData()
        .extractPayload()
        .result()
    }

    // The first one puts the process in its steady state.
    try await upload()

    let startThreads = threadCount()
    let sampler = PeakSampler()
    sampler.start()

    let elapsed = try await ContinuousClock().measure {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<uploads {
                group.addTask { try await upload() }
            }

            try await group.waitForAll()
        }
    }

    _ = sampler.stop()
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

    print(
        "RESULT executor=\(executor) uploads=\(uploads) kib=\(kibibytes) seconds=\(seconds) "
            + "uploads_per_s=\(Double(uploads) / seconds) threads_at_start=\(startThreads) "
            + "threads_peak=\(sampler.peakThreads)"
    )

case "images":
    #if canImport(AppKit)
    let port = arguments[2]
    let executor = resolveExecutor(named: arguments[3])
    let loads = Int(arguments[4])!
    let imageMebibytes = Int(arguments[5])!
    let cancelAfter = UInt64(arguments[6])!
    let interval = UInt64(arguments[7])!
    let settle = UInt64(arguments[8])!

    func serverCount(_ path: String) async throws -> Int {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        return Int(String(decoding: data, as: UTF8.self))!
    }

    let loader = RDLImageLoader()
    _ = try await serverCount("/reset")

    var tasks: [Task<Void, Never>] = []

    for index in 0..<loads {
        let load = Task {
            _ = try? await loader.load(id: "image-\(index)") {
                Session().requiredExecutor(executor)
                BaseURL(.http, host: "127.0.0.1:\(port)")
                Path("/slow/\(imageMebibytes)/\(index)")
            }
        }

        tasks.append(load)
        tasks.append(
            Task {
                try? await Task.sleep(nanoseconds: cancelAfter * 1_000_000)
                load.cancel()
            }
        )

        try await Task.sleep(nanoseconds: interval * 1_000_000)
    }

    for task in tasks {
        await task.value
    }

    try await Task.sleep(nanoseconds: settle * 1_000_000)
    let sent = try await serverCount("/sent")

    print(
        "RESULT executor=\(arguments[3]) loads=\(loads) image_mib=\(imageMebibytes) "
            + "full_mib=\(loads * imageMebibytes) sent_mib=\(String(format: "%.1f", Double(sent) / Double(mebibyte))) "
            + "sent_share=\(String(format: "%.3f", Double(sent) / Double(loads * imageMebibytes * mebibyte)))"
    )
    #else
    print("images needs AppKit")
    #endif

default:
    print("unknown mode \(arguments[1])")
}
