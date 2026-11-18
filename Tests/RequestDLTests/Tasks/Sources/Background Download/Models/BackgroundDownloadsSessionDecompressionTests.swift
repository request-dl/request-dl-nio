//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals
import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

import Foundation

/// Covers what `BackgroundDownloads.Session` does with a downloaded file whose request took over
/// `Accept-Encoding`: decoding it before it takes its place at `destination`.
///
/// Same approach as `BackgroundDownloadsSessionDelegateTests`: an ordinary `URLSession` whose
/// delegate is a fresh `BackgroundDownloads.Session`, with a `URLProtocol` stub serving the
/// response, so `downloadTask.response` is genuine and the callback runs exactly as it would for
/// a background transfer, which this harness has no entitlements to start.
struct BackgroundDownloadsSessionDecompressionTests {

    // MARK: - Decoding

    @Test
    func aCustomEncoding_isDecodedBeforeItTakesItsPlace() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            let plain = String(repeating: "a", count: 1_000) + String(repeating: "b", count: 777)
            let session = BackgroundDownloads.Session()
            session.keepDecompressors([Self.algorithm(RLEDecompressor())], for: "episode")

            // When
            let events = try await Self.download(
                id: "episode",
                to: destination,
                encoding: "rle",
                body: Self.rleEncode(plain),
                session: session
            )

            // Then
            #expect(try String(contentsOf: destination, encoding: .utf8) == plain)
            #expect(Self.terminal(events).count == 1)

            guard case .completed(let id, _) = try #require(Self.terminal(events).first) else {
                Issue.record("Expected .completed, got \(events)")
                return
            }
            #expect(id == "episode")
            #expect(Self.leftovers(beside: destination).isEmpty)
        }
    }

    /// More than one piece is read, so the decoder is fed across `decodingChunkSize` boundaries.
    @Test
    func aBodyLargerThanOnePiece_isDecodedWhole() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given: 150 000 plain bytes, each differing from the one before so no run merges, and
            // so 300 000 encoded ones: several pieces.
            let plain = String((0..<150_000).map { Character(UnicodeScalar(UInt8(97 + $0 % 26))) })
            let encoded = Self.rleEncode(plain)
            #expect(encoded.count > 64 * 1024 * 2)

            let session = BackgroundDownloads.Session()
            session.register(Self.algorithm(RLEDecompressor()))

            // When
            let events = try await Self.download(
                id: "big",
                to: destination,
                encoding: "RLE",
                body: encoded,
                session: session
            )

            // Then
            #expect(try String(contentsOf: destination, encoding: .utf8) == plain)
            #expect(Self.terminal(events).count == 1)
        }
    }

    @Test
    func aResponseWithoutAnEncoding_isMovedAsItCame() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            let session = BackgroundDownloads.Session()
            session.keepDecompressors([Self.algorithm(RLEDecompressor())], for: "plain")

            // When
            let events = try await Self.download(
                id: "plain",
                to: destination,
                encoding: nil,
                body: Array("not encoded".utf8),
                session: session
            )

            // Then
            #expect(try String(contentsOf: destination, encoding: .utf8) == "not encoded")
            #expect(Self.terminal(events).count == 1)
        }
    }

    @Test
    func identity_isMovedAsItCame() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            let session = BackgroundDownloads.Session()
            session.keepDecompressors([Self.algorithm(RLEDecompressor())], for: "identity")

            // When
            _ = try await Self.download(
                id: "identity",
                to: destination,
                encoding: "identity",
                body: Array("as is".utf8),
                session: session
            )

            // Then
            #expect(try String(contentsOf: destination, encoding: .utf8) == "as is")
        }
    }

    /// What a download scheduled by an older version, or one that left decoding to the system,
    /// has always been: `Content-Encoding` is there because CFNetwork decoded it and left the
    /// header, so decoding it again would corrupt it.
    @Test
    func aDownloadThatDidNotTakeOverAcceptEncoding_isNeverDecoded() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            let session = BackgroundDownloads.Session()
            session.register(Self.algorithm(RLEDecompressor()))

            // When
            _ = try await Self.download(
                id: "legacy",
                to: destination,
                encoding: "rle",
                body: Array("already decoded".utf8),
                session: session,
                acceptedEncodings: nil
            )

            // Then
            #expect(try String(contentsOf: destination, encoding: .utf8) == "already decoded")
        }
    }

    // MARK: - Relaunch

    /// The download finished in a launch that has none of the original `content`: nothing is
    /// scheduled in this process, only what the app registered.
    @Test
    func afterARelaunch_aRegisteredDecompressorDecodesIt() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            let session = BackgroundDownloads.Session()
            session.register(Self.algorithm(RLEDecompressor()))

            // When
            _ = try await Self.download(
                id: "relaunched",
                to: destination,
                encoding: "rle",
                body: Self.rleEncode("zzzz"),
                session: session
            )

            // Then
            #expect(try String(contentsOf: destination, encoding: .utf8) == "zzzz")
        }
    }

    @Test
    func afterARelaunch_withoutARegisteredDecompressor_failsAndKeepsWhatWasThere() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            try Data("previous".utf8).write(to: destination)
            let session = BackgroundDownloads.Session()

            // When
            let events = try await Self.download(
                id: "relaunched",
                to: destination,
                encoding: "rle",
                body: Self.rleEncode("zzzz"),
                session: session
            )

            // Then
            let error = try Self.failure(of: events)
            #expect((error as? BackgroundDownloadMissingDecompressorError)?.contentEncoding == "rle")
            #expect(try String(contentsOf: destination, encoding: .utf8) == "previous")
            #expect(Self.leftovers(beside: destination).isEmpty)
        }
    }

    // MARK: - Failures

    @Test
    func anEncodingThatWasNotAskedFor_failsAsUnsupported() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            try Data("previous".utf8).write(to: destination)
            let session = BackgroundDownloads.Session()
            session.keepDecompressors([Self.algorithm(RLEDecompressor())], for: "surprise")

            // When
            let events = try await Self.download(
                id: "surprise",
                to: destination,
                encoding: "zstd",
                body: Array("bytes".utf8),
                session: session
            )

            // Then
            #expect((try Self.failure(of: events) as? UnsupportedContentEncodingError)?.value == "zstd")
            #expect(try String(contentsOf: destination, encoding: .utf8) == "previous")
        }
    }

    @Test
    func stackedEncodings_failAsUnsupported() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            let session = BackgroundDownloads.Session()
            session.keepDecompressors([Self.algorithm(RLEDecompressor())], for: "stacked")

            // When
            let events = try await Self.download(
                id: "stacked",
                to: destination,
                encoding: "rle, rle",
                body: Self.rleEncode("aa"),
                session: session
            )

            // Then
            #expect((try Self.failure(of: events) as? UnsupportedContentEncodingError)?.value == "rle, rle")
        }
    }

    /// A body cut short is caught by `finish()`, and nothing it half-decoded takes the place of
    /// the file already there.
    @Test
    func aTruncatedBody_failsAndKeepsWhatWasThere() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            try Data("previous".utf8).write(to: destination)
            let session = BackgroundDownloads.Session()
            session.keepDecompressors([Self.algorithm(StrictDecompressor())], for: "cut")

            // When
            let events = try await Self.download(
                id: "cut",
                to: destination,
                encoding: "strict",
                body: [97, 3, 98],
                session: session
            )

            // Then
            #expect(try Self.failure(of: events) is StrictDecompressor.TruncatedError)
            #expect(try String(contentsOf: destination, encoding: .utf8) == "previous")
            #expect(Self.leftovers(beside: destination).isEmpty)
        }
    }

    @Test
    func anEmptyBody_isNotFinished() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            let session = BackgroundDownloads.Session()
            session.keepDecompressors([Self.algorithm(StrictDecompressor())], for: "empty")

            // When
            let events = try await Self.download(
                id: "empty",
                to: destination,
                encoding: "strict",
                body: [],
                session: session
            )

            // Then
            #expect(Self.terminal(events).count == 1)
            #expect(try Data(contentsOf: destination).isEmpty)
        }
    }

    // MARK: - taskDescription

    @Test
    func theAcceptedEncodings_surviveTheTaskDescription() {
        let description = BackgroundDownloads.Session.encode(
            id: "a",
            destination: URL(fileURLWithPath: "/tmp/a"),
            acceptedEncodings: ["rle", "zstd"]
        )

        #expect(BackgroundDownloads.Session.decodeAcceptedEncodings(description) == ["rle", "zstd"])
    }

    @Test
    func aDescriptionWithoutThem_decodesWithNone() {
        let description = BackgroundDownloads.Session.encode(id: "a", destination: URL(fileURLWithPath: "/tmp/a"))

        #expect(BackgroundDownloads.Session.decodeAcceptedEncodings(description) == nil)
    }

    // MARK: - Content-Encoding

    @Test(arguments: [
        (nil, []),
        ("", []),
        ("identity", []),
        ("RLE", ["rle"]),
        (" rle , Identity ", ["rle"]),
        ("rle,zstd", ["rle", "zstd"]),
    ] as [(String?, [String])])
    func contentEncodings_areLowercasedAndWithoutIdentity(_ header: String?, _ expected: [String]) throws {
        let response = HTTPURLResponse(
            url: try #require(URL(string: "https://example.invalid")),
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: header.map { ["Content-Encoding": $0] }
        )

        #expect(BackgroundDownloads.Session.contentEncodings(of: response) == expected)
    }

    // MARK: - Helpers

    private static func algorithm(_ decompressor: some Decompressor) -> any Internals.DecompressionAlgorithm {
        InternalsDecompressionAlgorithmAdapter(algorithm: decompressor)
    }

    /// Runs one download through `session`'s own delegate callbacks and returns every event it
    /// produced, once the terminal one has fired.
    private static func download(
        id: String,
        to destination: URL,
        encoding: String?,
        body: [UInt8],
        session: BackgroundDownloads.Session,
        acceptedEncodings: [String]? = ["rle", "strict"]
    ) async throws -> [BackgroundDownloads.Event] {
        let bodyFile = destination.deletingLastPathComponent()
            .appendingPathComponent("served-\(UUID().uuidString).bin")
        try Data(body).write(to: bodyFile)
        defer { try? FileManager.default.removeItem(at: bodyFile) }

        let collector = EventCollector()
        session.onEvent = { collector.append($0) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EncodedBodyURLProtocol.self]
        let urlSession = URLSession(configuration: configuration, delegate: session, delegateQueue: nil)
        defer { urlSession.invalidateAndCancel() }

        var request = URLRequest(url: try #require(URL(string: "https://example.invalid/file.bin")))
        request.setValue(bodyFile.path, forHTTPHeaderField: EncodedBodyURLProtocol.bodyFileHeader)
        if let encoding {
            request.setValue(encoding, forHTTPHeaderField: EncodedBodyURLProtocol.encodingHeader)
        }

        let task = urlSession.downloadTask(with: request)
        task.taskDescription = BackgroundDownloads.Session.encode(
            id: id,
            destination: destination,
            acceptedEncodings: acceptedEncodings
        )

        task.resume()
        await collector.waitForTerminalEvent()
        return collector.all
    }

    private static func terminal(_ events: [BackgroundDownloads.Event]) -> [BackgroundDownloads.Event] {
        events.filter {
            if case .progress = $0 { return false }
            return true
        }
    }

    private static func failure(of events: [BackgroundDownloads.Event]) throws -> any Error {
        guard case .failed(_, _, let error) = try #require(terminal(events).first) else {
            Issue.record("Expected .failed, got \(events)")
            throw CancellationError()
        }
        return error
    }

    /// Whatever the decoding left beside `destination` besides `destination` itself.
    private static func leftovers(beside destination: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)) ?? []
        return names.filter { $0 != destination.lastPathComponent }
    }

    /// A toy run-length codec: a flat sequence of (byte, count) pairs, count in `1...255`.
    private struct RLEDecompressor: Decompressor {
        var contentEncodingValue: String { "rle" }

        func callAsFunction() throws -> any DecompressorStream { Stream() }

        struct Stream: DecompressorStream {
            private var pendingByte: UInt8?

            mutating func callAsFunction(decompressing bytes: [UInt8]) throws -> [UInt8] {
                var output: [UInt8] = []
                for byte in bytes {
                    if let pending = pendingByte {
                        output.append(contentsOf: Array(repeating: pending, count: Int(byte)))
                        pendingByte = nil
                    } else {
                        pendingByte = byte
                    }
                }
                return output
            }

            func finish() throws -> [UInt8] { [] }
        }
    }

    /// The same codec, but a pair cut in half is an error, like a real truncated stream.
    private struct StrictDecompressor: Decompressor {
        struct TruncatedError: Error {}

        var contentEncodingValue: String { "strict" }

        func callAsFunction() throws -> any DecompressorStream { Stream() }

        struct Stream: DecompressorStream {
            private var inner = RLEDecompressor.Stream()
            private var isMidPair = false

            mutating func callAsFunction(decompressing bytes: [UInt8]) throws -> [UInt8] {
                for _ in bytes { isMidPair.toggle() }
                return try inner(decompressing: bytes)
            }

            func finish() throws -> [UInt8] {
                if isMidPair { throw TruncatedError() }
                return []
            }
        }
    }

    private static func rleEncode(_ string: String) -> [UInt8] {
        var output: [UInt8] = []
        let bytes = Array(string.utf8)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            var count = 1
            while index + count < bytes.count, bytes[index + count] == byte, count < 255 {
                count += 1
            }
            output.append(byte)
            output.append(UInt8(count))
            index += count
        }
        return output
    }
}

// MARK: - Test helpers

/// Serves the file named by the request's own header, with the `Content-Encoding` it names, so a
/// download task finishes with a genuine `HTTPURLResponse` and no network access.
private final class EncodedBodyURLProtocol: URLProtocol {

    static let bodyFileHeader = "X-Test-Body-File"
    static let encodingHeader = "X-Test-Encoding"

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard
            let url = request.url,
            let path = request.value(forHTTPHeaderField: Self.bodyFileHeader),
            let body = FileManager.default.contents(atPath: path)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        var headers = ["Content-Length": "\(body.count)"]
        if let encoding = request.value(forHTTPHeaderField: Self.encodingHeader) {
            headers["Content-Encoding"] = encoding
        }

        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Collects every event and lets a test wait for the first one that is not progress.
private final class EventCollector: @unchecked Sendable {

    private let lock = Lock()
    private var _all: [BackgroundDownloads.Event] = []
    private var isTerminal = false
    private var continuation: CheckedContinuation<Void, Never>?

    var all: [BackgroundDownloads.Event] {
        lock.withLock { _all }
    }

    func append(_ event: BackgroundDownloads.Event) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            _all.append(event)

            if case .progress = event { return nil }

            isTerminal = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }

    func waitForTerminalEvent() async {
        await withCheckedContinuation { continuation in
            let resumeNow = lock.withLock { () -> Bool in
                if isTerminal { return true }
                self.continuation = continuation
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }
}

#endif
