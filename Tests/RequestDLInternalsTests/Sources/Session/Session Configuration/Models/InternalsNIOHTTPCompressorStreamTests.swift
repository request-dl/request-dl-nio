//
// See LICENSE for this package's licensing information.
//

// `Internals.NIOHTTPCompressorStream` only exists under `canImport(NIOCore)`.
#if canImport(NIOCore)

import Foundation
import NIOCore
import NIOPosix
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

struct InternalsNIOHTTPCompressorStreamTests {

    // MARK: - Helpers

    private static let chunks: [Data] = (0..<6).map { index in
        Data(String(repeating: "chunk \(index) of a body worth compressing. ", count: 40).utf8)
    }

    private static func compress(
        _ algorithm: Internals.Compression.Algorithm,
        chunks: [Data] = chunks
    ) throws -> Data {
        var stream = try Internals.NIOHTTPCompressorStream(algorithm: algorithm)
        var output = Data()

        for chunk in chunks {
            var piece = try stream(compressing: Internals.Bytes(chunk))
            output.append(piece.asData())
        }

        var tail = try stream.finish()
        output.append(tail.asData())
        return output
    }

    // MARK: - Tests

    @Test(arguments: [Internals.Compression.Algorithm.gzip, .deflate])
    func compressing_offAnEventLoop_producesCompressedBytes(
        algorithm: Internals.Compression.Algorithm
    ) throws {
        let output = try Self.compress(algorithm)

        #expect(!output.isEmpty)
        #expect(output.count < Self.chunks.reduce(0) { $0 + $1.count })
    }

    /// An app that installs NIO as Swift Concurrency's global executor runs the code that feeds
    /// the compressor on an event loop thread, where waiting on an event loop future is a
    /// precondition failure in every build.
    @Test(arguments: [Internals.Compression.Algorithm.gzip, .deflate])
    func compressing_onAnEventLoopThread_doesNotTrapAndMatchesTheOutputFromElsewhere(
        algorithm: Internals.Compression.Algorithm
    ) async throws {
        let expected = try Self.compress(algorithm)

        let actual = try await NIOSingletons.posixEventLoopGroup.next().submit {
            try Self.compress(algorithm)
        }.get()

        #expect(actual == expected)
    }

    @Test
    func compressing_manyStreamsAtOnceOnEventLoopThreads_allFinish() async throws {
        let expected = try Self.compress(.gzip)
        let group = NIOSingletons.posixEventLoopGroup

        let outputs = try await completing(within: 30) {
            try await withThrowingTaskGroup(of: Data.self) { tasks in
                for _ in 0..<64 {
                    tasks.addTask {
                        try await group.next().submit { try Self.compress(.gzip) }.get()
                    }
                }

                var results: [Data] = []

                for try await output in tasks {
                    results.append(output)
                }

                return results
            }
        }

        #expect(outputs.count == 64)
        #expect(outputs.allSatisfy { $0 == expected })
    }

    @Test
    func compressing_aStreamCreatedOnOneEventLoopAndUsedOnAnother_works() async throws {
        let group = NIOSingletons.posixEventLoopGroup
        let loops = (0..<2).map { _ in group.next() }
        let expected = try Self.compress(.gzip)

        let box = StreamBox(try Internals.NIOHTTPCompressorStream(algorithm: .gzip))

        let output = try await loops[1].submit {
            try box.drive(Self.chunks)
        }.get()

        #expect(output == expected)
    }

    @Test
    func dropping_aStreamWithoutFinishing_onAnEventLoopThread_doesNotTrap() async throws {
        try await NIOSingletons.posixEventLoopGroup.next().submit {
            var stream = try Internals.NIOHTTPCompressorStream(algorithm: .gzip)
            _ = try stream(compressing: Internals.Bytes(Self.chunks[0]))
        }.get()
    }

    @Test
    func usingAStream_afterFinish_throwsInsteadOfWaiting() async throws {
        var stream = try Internals.NIOHTTPCompressorStream(algorithm: .gzip)
        _ = try stream(compressing: Internals.Bytes(Self.chunks[0]))
        _ = try stream.finish()

        let result = try await completing(within: 10) { [stream] in
            var stream = stream

            do {
                _ = try stream(compressing: Internals.Bytes(Self.chunks[0]))
                return false
            } catch {
                return true
            }
        }

        #expect(result)

        #expect(throws: (any Error).self) {
            try stream.finish()
        }
    }

    @Test
    func aFinishedStream_givesItsThreadBack() async throws {
        var stream = try Internals.NIOHTTPCompressorStream(algorithm: .gzip)
        let isRunning = stream.workerProbe
        _ = try stream(compressing: Internals.Bytes(Self.chunks[0]))
        #expect(isRunning())

        _ = try stream.finish()

        try await eventually { !isRunning() }
    }

    @Test
    func aDroppedStream_givesItsThreadBack() async throws {
        let isRunning: @Sendable () -> Bool

        do {
            var stream = try Internals.NIOHTTPCompressorStream(algorithm: .gzip)
            isRunning = stream.workerProbe
            _ = try stream(compressing: Internals.Bytes(Self.chunks[0]))
            #expect(isRunning())
        }

        try await eventually { !isRunning() }
    }
}

private final class StreamBox: @unchecked Sendable {

    private var stream: Internals.NIOHTTPCompressorStream

    init(_ stream: Internals.NIOHTTPCompressorStream) {
        self.stream = stream
    }

    func drive(_ chunks: [Data]) throws -> Data {
        var output = Data()

        for chunk in chunks {
            var piece = try stream(compressing: Internals.Bytes(chunk))
            output.append(piece.asData())
        }

        var tail = try stream.finish()
        output.append(tail.asData())
        return output
    }
}

#endif
