//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import Foundation
import NIOCore

/// The client side of the benchmark: plain AsyncHTTPClient, so that what is compared is the fork
/// at two versions and nothing of RequestDL's on top of it.
///
///     bench-client --server http://127.0.0.1:18080 --scenario download --scale 1
///
/// Prints one JSON line: how long the scenario took, how much CPU the process spent on it, how
/// many bytes crossed and how many requests were made.

struct Options {
    var server = "http://127.0.0.1:18080"
    var scenario = "small"
    var scale = 1.0
}

private func parse() -> Options {
    var options = Options()
    var arguments = CommandLine.arguments.dropFirst()

    while let argument = arguments.popFirst() {
        switch argument {
        case "--server": options.server = arguments.popFirst() ?? options.server
        case "--scenario": options.scenario = arguments.popFirst() ?? options.scenario
        case "--scale": options.scale = Double(arguments.popFirst() ?? "") ?? options.scale
        default: break
        }
    }

    return options
}

/// What one scenario is: how many requests, how many at once, and how big each is.
struct Scenario {
    let requests: Int
    let concurrency: Int
    let bytes: Int

    /// `scale` shrinks the sizes and the counts, for a quick check that the harness runs; the real
    /// numbers are taken at 1.
    static func named(_ name: String, scale: Double) -> Scenario? {
        func scaled(_ value: Int) -> Int { Swift.max(1, Int(Double(value) * scale)) }

        switch name {
        case "download": return Scenario(requests: 16, concurrency: 16, bytes: scaled(256 * 1_048_576))
        case "upload": return Scenario(requests: 8, concurrency: 8, bytes: scaled(128 * 1_048_576))
        case "small": return Scenario(requests: scaled(60_000), concurrency: 32, bytes: 0)
        default: return nil
        }
    }
}

/// A body of `count` zero bytes, handed over in buffers of 64 KiB as it is asked for.
private struct Chunks: AsyncSequence, Sendable {

    typealias Element = ByteBuffer

    let count: Int

    struct AsyncIterator: AsyncIteratorProtocol {
        var remaining: Int
        let chunk = ByteBuffer(repeating: 0, count: 64 * 1_024)

        mutating func next() async -> ByteBuffer? {
            guard remaining > 0 else {
                return nil
            }

            let size = Swift.min(remaining, chunk.readableBytes)
            remaining -= size

            var buffer = chunk
            buffer.moveWriterIndex(to: size)
            return buffer
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(remaining: count)
    }
}

private func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)

    func seconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }

    return seconds(usage.ru_utime) + seconds(usage.ru_stime)
}

private func run(_ client: HTTPClient, options: Options, scenario: Scenario) async throws -> Int {
    @Sendable func perform(_ index: Int) async throws -> Int {
        var request: HTTPClientRequest

        switch options.scenario {
        case "download":
            request = HTTPClientRequest(url: "\(options.server)/download?bytes=\(scenario.bytes)")
        case "upload":
            request = HTTPClientRequest(url: "\(options.server)/upload")
            request.method = .POST
            request.body = .stream(Chunks(count: scenario.bytes), length: .known(Int64(scenario.bytes)))
        default:
            request = HTTPClientRequest(url: "\(options.server)/small")
        }

        let response = try await client.execute(request, timeout: .seconds(900))
        var received = 0

        for try await buffer in response.body {
            received += buffer.readableBytes
        }

        return options.scenario == "upload" ? scenario.bytes : received
    }

    // At most `concurrency` at once, a new one as each one ends.
    return try await withThrowingTaskGroup(of: Int.self) { group in
        var next = 0
        var total = 0

        while next < Swift.min(scenario.concurrency, scenario.requests) {
            let index = next
            group.addTask { try await perform(index) }
            next += 1
        }

        while let bytes = try await group.next() {
            total += bytes

            if next < scenario.requests {
                let index = next
                group.addTask { try await perform(index) }
                next += 1
            }
        }

        return total
    }
}

let options = parse()

guard let scenario = Scenario.named(options.scenario, scale: options.scale) else {
    FileHandle.standardError.write(Data("unknown scenario \(options.scenario)\n".utf8))
    exit(2)
}

let client = HTTPClient(eventLoopGroupProvider: .singleton)

do {
    let cpuBefore = cpuSeconds()
    let start = DispatchTime.now().uptimeNanoseconds
    let bytes = try await run(client, options: options, scenario: scenario)
    let wall = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    let cpu = cpuSeconds() - cpuBefore

    print(
        """
        {"scenario":"\(options.scenario)","scale":\(options.scale),"wallSeconds":\(wall),\
        "cpuSeconds":\(cpu),"bytes":\(bytes),"requests":\(scenario.requests)}
        """
    )

    try await client.shutdown()
} catch {
    FileHandle.standardError.write(Data("failed: \(error)\n".utf8))
    try? await client.shutdown()
    exit(1)
}
