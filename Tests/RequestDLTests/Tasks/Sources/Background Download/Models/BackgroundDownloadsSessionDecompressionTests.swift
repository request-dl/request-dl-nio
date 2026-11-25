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

            // When
            let events = try await Self.download(
                id: "episode",
                scheduledWith: [Self.algorithm(RLEDecompressor())],
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

    /// The directory the decoded file is made in is the system's own, not beside `destination`, so
    /// `leftovers(beside:)` cannot see it: a session that records the ones it made can.
    @Test
    func theDirectoryTheDecodedFileWasMadeIn_isRemovedWhateverTheOutcome() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            let directories = LockedValueBox<[URL]>([])
            let session = Self.session(recording: directories)
            session.register(Self.algorithm(RLEDecompressor()))

            // Decoded and moved.
            let completed = try await Self.download(
                id: "completed",
                to: destination,
                encoding: "rle",
                body: Self.rleEncode("aabb"),
                session: session
            )
            #expect(Self.terminal(completed).count == 1)
            #expect(directories.withLockedValue { $0 }.count == 1)

            // Decoded and refused, for passing the limit.
            let refused = try await Self.download(
                id: "refused",
                to: destination,
                encoding: "rle",
                body: Self.rleEncode(Self.bomb),
                session: session,
                limit: .size(10)
            )
            #expect(try Self.failure(of: refused) is BackgroundDownloadDecompressionLimitError)

            // Decoded and failed, for ending in the middle of a pair.
            session.register(Self.algorithm(StrictDecompressor()))
            let truncated = try await Self.download(
                id: "truncated",
                to: destination,
                encoding: "strict",
                body: [97],
                session: session
            )
            #expect(try Self.failure(of: truncated) is StrictDecompressor.TruncatedError)

            let made = directories.withLockedValue { $0 }
            #expect(made.count == 3)
            #expect(made.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
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

            // When
            let events = try await Self.download(
                id: "plain",
                scheduledWith: [Self.algorithm(RLEDecompressor())],
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

            // When
            _ = try await Self.download(
                id: "identity",
                scheduledWith: [Self.algorithm(RLEDecompressor())],
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

            // When
            let events = try await Self.download(
                id: "surprise",
                scheduledWith: [Self.algorithm(RLEDecompressor())],
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

            // When
            let events = try await Self.download(
                id: "stacked",
                scheduledWith: [Self.algorithm(RLEDecompressor())],
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

            // When
            let events = try await Self.download(
                id: "cut",
                scheduledWith: [Self.algorithm(StrictDecompressor())],
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

    /// `finish()` of this decoder always throws, so the body is only "not finished" if it was
    /// never asked: a body that never had a byte is no stream to finish.
    @Test
    func anEmptyBody_isNotFinished() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            let session = BackgroundDownloads.Session()

            // When
            let events = try await Self.download(
                id: "empty",
                scheduledWith: [Self.algorithm(NeverFinishesDecompressor())],
                to: destination,
                encoding: "never",
                body: [],
                session: session,
                acceptedEncodings: ["never"]
            )

            // Then
            guard case .completed = try #require(Self.terminal(events).first) else {
                Issue.record("Expected .completed, got \(events)")
                return
            }
            #expect(try Data(contentsOf: destination).isEmpty)
        }
    }

    @Test
    func aBodyWithBytes_isFinished() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            let session = BackgroundDownloads.Session()

            // When
            let events = try await Self.download(
                id: "finished",
                scheduledWith: [Self.algorithm(NeverFinishesDecompressor())],
                to: destination,
                encoding: "never",
                body: [1],
                session: session,
                acceptedEncodings: ["never"]
            )

            // Then
            #expect(try Self.failure(of: events) is NeverFinishesDecompressor.FinishedError)
        }
    }

    /// Nothing but what the request asked for is decoded, a registered decompressor included.
    @Test
    func anEncodingThatWasNotAskedFor_isNotDecodedEvenWhenRegistered() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            let session = BackgroundDownloads.Session()
            session.register(Self.algorithm(RLEDecompressor()))

            // When
            let events = try await Self.download(
                id: "unasked",
                to: destination,
                encoding: "rle",
                body: Self.rleEncode("aa"),
                session: session,
                acceptedEncodings: ["strict"]
            )

            // Then
            #expect((try Self.failure(of: events) as? UnsupportedContentEncodingError)?.value == "rle")
        }
    }

    /// CFNetwork decodes `gzip`, `deflate` and `br` whatever `Accept-Encoding` says, and keeps the
    /// header. An app's own decompressor for one of those names (`br` under `.nio`, which has no
    /// brotli) was run over the file the system had already decoded.
    @Test(arguments: ["gzip", "deflate", "br"])
    func aDecompressorForAnEncodingTheSystemDecodes_isNotRunOverTheFileItDecoded(_ encoding: String) async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given: the file is plain already, as the system hands it over.
            let plain = "plain: the system decoded this before the delegate saw it"
            let session = BackgroundDownloads.Session()

            // When
            let events = try await Self.download(
                id: "native",
                scheduledWith: [Self.algorithm(MustNotRunDecompressor(encoding: encoding))],
                to: destination,
                encoding: encoding,
                body: Array(plain.utf8),
                session: session,
                acceptedEncodings: [encoding]
            )

            // Then
            guard case .completed = try #require(Self.terminal(events).first) else {
                Issue.record("Expected .completed, got \(events)")
                return
            }
            #expect(try String(contentsOf: destination, encoding: .utf8) == plain)
            #expect(Self.leftovers(beside: destination).isEmpty)
        }
    }

    // MARK: - Counters

    /// The counters of what was read and written are 64 bits wide, so a file that passes `Int`'s
    /// range on a 32-bit platform is a limit to report instead of an overflow that traps.
    @Test
    func theLimit_isCheckedAgainstCountsPastThirtyTwoBits() throws {
        let beyond = UInt64(Int32.max) * 4

        #expect(throws: BackgroundDownloadDecompressionLimitError.self) {
            try BackgroundDownloads.Session.enforce(.size(Int(Int32.max)), read: 1, written: beyond)
        }

        #expect(throws: BackgroundDownloadDecompressionLimitError.self) {
            try BackgroundDownloads.Session.enforce(.ratio(2), read: UInt64(Int32.max), written: beyond)
        }

        try BackgroundDownloads.Session.enforce(.size(Int(Int32.max)), read: beyond, written: UInt64(Int32.max))
        try BackgroundDownloads.Session.enforce(.ratio(4), read: beyond, written: beyond)
        try BackgroundDownloads.Session.enforce(.none, read: .max, written: .max)
    }

    // MARK: - Pieces

    /// A decoder's own unit of input (a pair, here) cut by the boundary between two reads.
    @Test(arguments: [1, 2, 3, 5, 64 * 1024])
    func aBoundaryInsideAUnitOfInput_isDecodedAcrossReads(_ chunkSize: Int) async throws {
        try await withTemporaryFileURL("input.bin") { input in
            let output = input.deletingLastPathComponent().appendingPathComponent("output.bin")
            let plain = "aaabbbbcccccdddddd"
            try Data(Self.rleEncode(plain)).write(to: input)
            FileManager.default.createFile(atPath: output.path, contents: nil)

            try BackgroundDownloads.Session.decode(
                from: input,
                to: output,
                using: Self.algorithm(RLEDecompressor()),
                chunkSize: chunkSize
            )

            #expect(try String(contentsOf: output, encoding: .utf8) == plain)
        }
    }

    // MARK: - Limit

    /// 1 000 bytes, from 8.
    private static let bomb = String(repeating: "a", count: 1_000)

    @Test(
        arguments: [
            Internals.Decompression.Limit.size(999),
            .size(0),
            .ratio(124),
            .ratio(1),
        ]
    )
    func aLimitThatTheDecodedFilePasses_stopsTheDecoding(_ limit: Internals.Decompression.Limit) async throws {
        try await withTemporaryFileURL("input.bin") { input in
            let output = input.deletingLastPathComponent().appendingPathComponent("output.bin")
            try Data(Self.rleEncode(Self.bomb)).write(to: input)
            FileManager.default.createFile(atPath: output.path, contents: nil)

            #expect(throws: BackgroundDownloadDecompressionLimitError.self) {
                try BackgroundDownloads.Session.decode(
                    from: input,
                    to: output,
                    using: Self.algorithm(RLEDecompressor()),
                    limit: limit
                )
            }
        }
    }

    /// What is written is never past the limit: the piece that passes it is not written.
    @Test
    func aLimitThatTheDecodedFilePasses_writesNothingPastIt() async throws {
        try await withTemporaryFileURL("input.bin") { input in
            let output = input.deletingLastPathComponent().appendingPathComponent("output.bin")
            try Data(Self.rleEncode(Self.bomb)).write(to: input)
            FileManager.default.createFile(atPath: output.path, contents: nil)

            // Two bytes at a time: one pair, so 255 bytes more on each read.
            _ = try? BackgroundDownloads.Session.decode(
                from: input,
                to: output,
                using: Self.algorithm(RLEDecompressor()),
                limit: .size(600),
                chunkSize: 2
            )

            #expect(try Data(contentsOf: output).count == 510)
        }
    }

    @Test(
        arguments: [
            Internals.Decompression.Limit.none,
            .size(1_000),
            .size(Int.max),
            .ratio(125),
            .ratio(Int.max),
        ]
    )
    func aLimitThatTheDecodedFileDoesNotPass_isDecodedWhole(_ limit: Internals.Decompression.Limit) async throws {
        try await withTemporaryFileURL("input.bin") { input in
            let output = input.deletingLastPathComponent().appendingPathComponent("output.bin")
            try Data(Self.rleEncode(Self.bomb)).write(to: input)
            FileManager.default.createFile(atPath: output.path, contents: nil)

            try BackgroundDownloads.Session.decode(
                from: input,
                to: output,
                using: Self.algorithm(RLEDecompressor()),
                limit: limit
            )

            #expect(try String(contentsOf: output, encoding: .utf8) == Self.bomb)
        }
    }

    @Test
    func aDownloadThatExpandsPastTheLimit_failsAndKeepsWhatWasThere() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            try Data("previous".utf8).write(to: destination)
            let session = BackgroundDownloads.Session()
            session.register(Self.algorithm(RLEDecompressor()))

            // When
            let events = try await Self.download(
                id: "bomb",
                to: destination,
                encoding: "rle",
                body: Self.rleEncode(Self.bomb),
                session: session,
                limit: .size(500)
            )

            // Then
            let error = try Self.failure(of: events)
            #expect((error as? BackgroundDownloadDecompressionLimitError)?.limit == .size(500))
            #expect(try String(contentsOf: destination, encoding: .utf8) == "previous")
            #expect(Self.leftovers(beside: destination).isEmpty)
        }
    }

    @Test
    func theLimit_survivesInTheTaskDescription() {
        for limit: Internals.Decompression.Limit in [.none, .size(10), .ratio(3)] {
            let description = BackgroundDownloads.Session.encode(
                id: "a",
                destination: URL(fileURLWithPath: "/tmp/a"),
                decompressionLimit: limit
            )

            #expect(BackgroundDownloads.Session.decodeDecompressionLimit(description) == limit)
        }

        #expect(BackgroundDownloads.Session.decodeDecompressionLimit(nil) == .none)
    }

    // MARK: - Accept-Encoding

    @Test
    func aListOfWhatTheSystemDecodes_leavesAcceptEncodingAlone() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.invalid")))

        let algorithms = try BackgroundDownloads.Session.takingOverAcceptEncoding(
            of: &request,
            for: .enabled(
                algorithms: [Self.algorithm(GzipAlgorithm()), Self.algorithm(DeflateAlgorithm())],
                limit: .none
            )
        )

        #expect(algorithms == nil)
        #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == nil)
    }

    @Test
    func disabled_leavesAcceptEncodingAlone() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.invalid")))

        let algorithms = try BackgroundDownloads.Session.takingOverAcceptEncoding(of: &request, for: .disabled)

        #expect(algorithms == nil)
        #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == nil)
    }

    @Test(
        arguments: [
            ["gzip"], ["deflate"], ["br"], ["gzip", "rle"], ["rle", "deflate"],
        ] as [[String]]
    )
    func aSystemDecodedAlgorithmNextToACustomOne_isRefused(_ names: [String]) throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.invalid")))
        let algorithms: [any Internals.DecompressionAlgorithm] = names.map {
            switch $0 {
            case "gzip": Self.algorithm(GzipAlgorithm())
            case "deflate": Self.algorithm(DeflateAlgorithm())
            case "br": Self.algorithm(BrotliURLSessionOnlyAlgorithm())
            default: Self.algorithm(RLEDecompressor())
            }
        }
        let mixed = algorithms.contains { $0.contentEncodingValue == "rle" }

        do {
            _ = try BackgroundDownloads.Session.takingOverAcceptEncoding(
                of: &request,
                for: .enabled(algorithms: algorithms, limit: .none)
            )
            #expect(!mixed, "a mixed list must be refused")
        } catch let error as BackgroundDownloadUnsupportedConfigurationError {
            #expect(mixed)
            guard case .nativeAlgorithmNextToCustomAlgorithm = error.reason else {
                Issue.record("Expected .nativeAlgorithmNextToCustomAlgorithm, got \(error.reason)")
                return
            }
            #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == nil)
        }
    }

    @Test
    func aCustomAlgorithm_takesOverAcceptEncoding() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.invalid")))
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")

        let algorithms = try BackgroundDownloads.Session.takingOverAcceptEncoding(
            of: &request,
            for: .enabled(algorithms: [Self.algorithm(RLEDecompressor())], limit: .none)
        )

        #expect(algorithms?.map(\.contentEncodingValue) == ["rle"])
        #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == "rle")
    }

    // MARK: - Resuming

    @Test
    func aResumedDownloadWhoseRequestDidNotTakeOverAcceptEncoding_isNotDecoded() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.invalid")))
        let algorithms = [Self.algorithm(RLEDecompressor())]

        #expect(BackgroundDownloads.Session.decompression(algorithms, resumedFrom: request) == nil)

        request.setValue("rle", forHTTPHeaderField: "Accept-Encoding")
        #expect(BackgroundDownloads.Session.decompression(algorithms, resumedFrom: request)?.count == 1)
    }

    /// The request that stopped took over `Accept-Encoding`, so the file is encoded, whatever the
    /// `content` passed when continuing says: the encodings come from the header and the
    /// registered decompressors decode, or the download fails. It must never be `nil`, which
    /// hands the encoded file to `destination` as `.completed`.
    @Test
    func aResumedDownloadWhoseContentLostTheAlgorithms_readsThemFromTheRequest() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.invalid")))
        request.setValue("rle, Custom;q=0.5", forHTTPHeaderField: "Accept-Encoding")

        #expect(BackgroundDownloads.Session.acceptedEncodings(nil, resumedFrom: request) == ["rle", "custom"])
    }

    @Test
    func aResumedDownloadWhoseContentLostTheAlgorithms_isNotDecodedWhenTheRequestAskedForTheSystemOnly() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.invalid")))

        #expect(BackgroundDownloads.Session.acceptedEncodings(nil, resumedFrom: request) == nil)

        for header in ["gzip, deflate", "br;q=1.0, gzip", "identity", "*"] {
            request.setValue(header, forHTTPHeaderField: "Accept-Encoding")
            #expect(BackgroundDownloads.Session.acceptedEncodings(nil, resumedFrom: request) == nil)
        }
    }

    @Test
    func aResumedDownload_keepsWhatTheRequestAndContentAgreeOn() throws {
        var request = URLRequest(url: try #require(URL(string: "https://example.invalid")))
        let algorithms = [Self.algorithm(RLEDecompressor())]

        // No `Accept-Encoding`: the system decoded it, whatever `content` lists.
        #expect(BackgroundDownloads.Session.acceptedEncodings(algorithms, resumedFrom: request) == nil)

        request.setValue("rle", forHTTPHeaderField: "Accept-Encoding")
        #expect(BackgroundDownloads.Session.acceptedEncodings(algorithms, resumedFrom: request) == ["rle"])

        // No request: nothing to contradict `content`.
        #expect(BackgroundDownloads.Session.acceptedEncodings(algorithms, resumedFrom: nil) == ["rle"])
        #expect(BackgroundDownloads.Session.acceptedEncodings(nil, resumedFrom: nil) == nil)
    }

    @Test
    func aResumedDownloadWhoseContentLostTheAlgorithms_failsWithoutARegisteredDecompressor() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given: the encodings the resumed request lists, as `schedule(resumeData:)` keeps them
            var request = URLRequest(url: try #require(URL(string: "https://example.invalid")))
            request.setValue("rle", forHTTPHeaderField: "Accept-Encoding")
            let accepted = try #require(BackgroundDownloads.Session.acceptedEncodings(nil, resumedFrom: request))

            try Data("previous".utf8).write(to: destination)

            // When
            let events = try await Self.download(
                id: "resumed",
                to: destination,
                encoding: "rle",
                body: Self.rleEncode("aaa"),
                session: BackgroundDownloads.Session(),
                acceptedEncodings: accepted
            )

            // Then
            let error = try Self.failure(of: events)
            #expect((error as? BackgroundDownloadMissingDecompressorError)?.contentEncoding == "rle")
            #expect(try String(contentsOf: destination, encoding: .utf8) == "previous")
        }
    }

    @Test
    func aResumedDownloadWhoseContentLostTheAlgorithms_isDecodedByARegisteredDecompressor() async throws {
        try await withTemporaryFileURL("destination.txt") { destination in
            // Given
            var request = URLRequest(url: try #require(URL(string: "https://example.invalid")))
            request.setValue("rle", forHTTPHeaderField: "Accept-Encoding")
            let accepted = try #require(BackgroundDownloads.Session.acceptedEncodings(nil, resumedFrom: request))

            let session = BackgroundDownloads.Session()
            session.register(Self.algorithm(RLEDecompressor()))

            // When
            let events = try await Self.download(
                id: "resumed",
                to: destination,
                encoding: "rle",
                body: Self.rleEncode("aaabb"),
                session: session,
                acceptedEncodings: accepted
            )

            // Then
            #expect(Self.terminal(events).count == 1)
            #expect(try String(contentsOf: destination, encoding: .utf8) == "aaabb")
        }
    }

    @Test
    func aResumedDownloadWithoutARequest_keepsWhatWasConfigured() {
        let algorithms = [Self.algorithm(RLEDecompressor())]

        #expect(BackgroundDownloads.Session.decompression(algorithms, resumedFrom: nil)?.count == 1)
        #expect(BackgroundDownloads.Session.decompression(nil, resumedFrom: nil) == nil)
    }

    // MARK: - Registry

    /// Forgetting one task's algorithms leaves another's, even under the same `id`: a download
    /// cancelled for its resume data and scheduled again is a new task whose predecessor's
    /// completion arrives after it.
    @Test
    func forgettingATask_leavesTheNewerOneUnderTheSameID() throws {
        let session = BackgroundDownloads.Session()
        let url = try #require(URL(string: "https://example.invalid"))
        let urlSession = URLSession(configuration: .ephemeral)
        defer { urlSession.invalidateAndCancel() }

        let old = urlSession.downloadTask(with: url)
        let new = urlSession.downloadTask(with: url)
        session.keepDecompressors([Self.algorithm(RLEDecompressor())], for: old)
        session.keepDecompressors([Self.algorithm(RLEDecompressor())], for: new)

        session.forgetDecompressors(for: old)

        #expect(session.decompressor(forEncoding: "rle", task: old) == nil)
        #expect(session.decompressor(forEncoding: "rle", task: new) != nil)
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

    @Test(
        arguments: [
            (nil, []),
            ("", []),
            ("identity", []),
            ("RLE", ["rle"]),
            (" rle , Identity ", ["rle"]),
            ("rle,zstd", ["rle", "zstd"]),
        ] as [(String?, [String])]
    )
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
        scheduledWith algorithms: [any Internals.DecompressionAlgorithm]? = nil,
        to destination: URL,
        encoding: String?,
        body: [UInt8],
        session: BackgroundDownloads.Session,
        acceptedEncodings: [String]? = ["rle", "strict"],
        limit: Internals.Decompression.Limit = .none
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
        session.keepDecompressors(algorithms, for: task)
        task.taskDescription = BackgroundDownloads.Session.encode(
            id: id,
            destination: destination,
            acceptedEncodings: acceptedEncodings,
            decompressionLimit: limit
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

    /// A session that makes the directories of its decoded files as the system does, and records them.
    private static func session(recording directories: LockedValueBox<[URL]>) -> BackgroundDownloads.Session {
        BackgroundDownloads.Session { destination in
            let directory = try BackgroundDownloads.Session.systemReplacementDirectory(destination)
            directories.withLockedValue { $0.append(directory) }
            return directory
        }
    }

    /// Whatever the decoding left beside `destination` besides `destination` itself.
    private static func leftovers(beside destination: URL) -> [String] {
        let names =
            (try? FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)) ?? []
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

    /// Reads every byte and then refuses to finish.
    /// An app's own decompressor under a name the system decodes: running it at all is the failure.
    private struct MustNotRunDecompressor: Decompressor {
        struct RanError: Error {}

        let encoding: String

        var contentEncodingValue: String { encoding }

        func callAsFunction() throws -> any DecompressorStream { throw RanError() }
    }

    private struct NeverFinishesDecompressor: Decompressor {
        struct FinishedError: Error {}

        var contentEncodingValue: String { "never" }

        func callAsFunction() throws -> any DecompressorStream { Stream() }

        struct Stream: DecompressorStream {
            mutating func callAsFunction(decompressing bytes: [UInt8]) throws -> [UInt8] { bytes }
            func finish() throws -> [UInt8] { throw FinishedError() }
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
