//
// See LICENSE for this package's licensing information.
//

import Foundation
import RequestDL

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// Measurements of what the client costs in memory and CPU, through the public API only, so the
// same binary can be built against any revision of the package (see Package.swift). Each one
// prints one or two lines starting with `RESULT`.
//
//   memory-probe <scenario> <port> <nio|urlSession> <arguments>
//
//   download <MiB> <data|stream>
//       One download of that many MiB, after a warm-up: through `DataTask`, which keeps the body,
//       or through `DownloadTask`, which hands it out in pieces.
//   upload <MiB>
//       One upload of a body of that many MiB, after a warm-up.
//   small <count> <concurrency>
//       That many small GETs, that many at a time.
//   redirect <count>
//       That many sequential GETs under a redirect strategy, then the memory and threads again
//       after the process has had time to release what it is going to.

let arguments = CommandLine.arguments

guard arguments.count >= 4 else {
    print("usage: memory-probe <download|upload|small|redirect> <port> <nio|urlSession> <arguments>")
    exit(2)
}

let scenario = arguments[1]
let port = arguments[2]
let mebibyte = 1_024 * 1_024

#if canImport(NIOCore)
let executor: Session.Executor = arguments[3] == "nio" ? .nio : .urlSession
#else
let executor: Session.Executor = .urlSession
#endif

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

/// The CPU this process has used so far, user and system, in seconds.
func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)

    func seconds(_ time: timeval) -> Double {
        Double(time.tv_sec) + Double(time.tv_usec) / 1e6
    }

    return seconds(usage.ru_utime) + seconds(usage.ru_stime)
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
                lock.withLock { peak = max(peak, current) }
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
        }
    }

    func stop() -> Int {
        task?.cancel()
        return lock.withLock { max(peak, residentBytes()) }
    }
}

func mebibytes(_ bytes: Int) -> String {
    String(format: "%.1f", Double(bytes) / Double(mebibyte))
}

func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

/// Runs `block` and prints what it took: time, CPU, and the resident memory before, at the peak and
/// after. `block` answers how many units of work it did.
func measure(_ label: String, extra: String = "", _ block: () async throws -> Int) async throws {
    let before = residentBytes()
    let cpuBefore = cpuSeconds()
    let sampler = PeakSampler()
    sampler.start()

    var units = 0
    let elapsed = try await ContinuousClock().measure { units = try await block() }

    let peak = sampler.stop()
    let after = residentBytes()

    print(
        "RESULT scenario=\(label) executor=\(executor) units=\(units) seconds=\(seconds(elapsed)) "
            + "cpu=\(cpuSeconds() - cpuBefore) before_mib=\(mebibytes(before)) peak_mib=\(mebibytes(peak)) "
            + "grew_mib=\(mebibytes(peak - before)) after_mib=\(mebibytes(after)) threads=\(threadCount()) \(extra)"
    )
}

switch scenario {
case "download":
    let size = Int(arguments[4])! * mebibyte
    let mode = arguments[5]

    func run(_ bytes: Int) async throws -> Int {
        if mode == "data" {
            let result = try await DataTask {
                Session().requiredExecutor(executor)
                BaseURL(.http, host: "127.0.0.1:\(port)")
                Path("/download")
                Query(name: "bytes", value: bytes)
            }
            .result()

            return result.payload.count
        }

        let result = try await DownloadTask {
            Session().requiredExecutor(executor)
            BaseURL(.http, host: "127.0.0.1:\(port)")
            Path("/download")
            Query(name: "bytes", value: bytes)
        }
        .result()

        var received = 0

        for try await chunk in result.payload {
            received += chunk.count
        }

        return received
    }

    // The first request puts the process in its steady state (connection, buffers), so what is
    // measured next is the body and not the start up.
    _ = try await run(8 * mebibyte)
    try await measure("download-\(mode)") { try await run(size) }

case "upload":
    let size = Int(arguments[4])! * mebibyte
    let body = Data(repeating: 0x41, count: size)

    func run(_ data: Data) async throws {
        _ = try await UploadTask {
            Session().requiredExecutor(executor)
            BaseURL(.http, host: "127.0.0.1:\(port)")
            Path("/upload")
            RequestMethod(.put)
            Payload(data: data)
        }
        .collectData()
        .extractPayload()
        .result()
    }

    try await run(Data(repeating: 0x41, count: 8 * mebibyte))
    try await measure("upload") {
        try await run(body)
        return size
    }

case "small":
    let count = Int(arguments[4])!
    let concurrency = Int(arguments[5])!

    func one() async throws {
        _ = try await DataTask {
            Session().requiredExecutor(executor)
            BaseURL(.http, host: "127.0.0.1:\(port)")
            Path("/small")
        }
        .result()
    }

    for _ in 0..<20 { try await one() }

    try await measure("small", extra: "count=\(count)") {
        try await withThrowingTaskGroup(of: Void.self) { group in
            var started = 0

            for _ in 0..<min(concurrency, count) {
                group.addTask { try await one() }
                started += 1
            }

            while try await group.next() != nil {
                if started < count {
                    group.addTask { try await one() }
                    started += 1
                }
            }
        }

        return count
    }

case "redirect":
    let count = Int(arguments[4])!

    func one() async throws {
        _ = try await DataTask {
            Session()
                .requiredExecutor(executor)
                .onRedirect { context in .follow(context.redirectRequest) }
            BaseURL(.http, host: "127.0.0.1:\(port)")
            Path("/redirect")
        }
        .result()
    }

    for _ in 0..<5 { try await one() }

    try await measure("redirect", extra: "count=\(count)") {
        for _ in 0..<count { try await one() }
        return count
    }

    // Let anything that is going to be released be released, then read memory and threads again.
    try await Task.sleep(nanoseconds: 3_000_000_000)
    print("RESULT scenario=redirect-settled after_mib=\(mebibytes(residentBytes())) threads=\(threadCount())")

default:
    print("unknown scenario: \(scenario)")
    exit(2)
}
