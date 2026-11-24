//
// See LICENSE for this package's licensing information.
//

@_spi(Testing) import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

/// How the answer to the completeness probe is read.
struct CompletenessProbeVerdictTests {

    private typealias Probe = Internals.CacheControl.CompletenessProbe

    private func head(_ code: UInt, _ headers: [(String, String)]) -> Internals.ResponseHead {
        .init(
            url: "https://example.com/resource",
            status: .init(code: code, reason: ""),
            version: .init(minor: 1, major: 1),
            headers: headers.map { .init(name: $0.0, value: $0.1) },
            isKeepAlive: true
        )
    }

    @Test
    func verdict_whenThereIsNothingAfterTheBytesReceived_isComplete() {
        let answer = head(416, [("Content-Range", "bytes */1000")])

        #expect(Probe.verdict(of: answer, receivedBytes: 1_000) == .complete)
    }

    @Test
    func verdict_whenTheRepresentationIsAnotherLength_isUndecided() {
        let answer = head(416, [("Content-Range", "bytes */2000")])

        #expect(Probe.verdict(of: answer, receivedBytes: 1_000) == .undecided)
    }

    @Test
    func verdict_whenTheRepresentationIsShorterThanWhatWasReceived_isUndecided() {
        // The resource changed since the body was read: it is now shorter than what arrived, so
        // the answer says nothing of whether what arrived was whole.
        let answer = head(416, [("Content-Range", "bytes */500")])

        #expect(Probe.verdict(of: answer, receivedBytes: 1_000) == .undecided)
    }

    @Test
    func verdict_whenTheUnsatisfiedRangeSaysNothingOfTheLength_isUndecided() {
        #expect(Probe.verdict(of: head(416, []), receivedBytes: 1_000) == .undecided)
        #expect(Probe.verdict(of: head(416, [("Content-Range", "bytes */*")]), receivedBytes: 1_000) == .undecided)
    }

    @Test
    func verdict_whenTheServerHadTheNextByte_isTruncated() {
        let answer = head(206, [("Content-Range", "bytes 1000-1000/2000")])

        #expect(Probe.verdict(of: answer, receivedBytes: 1_000) == .truncated)
    }

    @Test(arguments: [200, 304, 404, 500, 503])
    func verdict_whenTheServerDidNotAnswerTheRange_isUndecided(_ code: UInt) {
        #expect(Probe.verdict(of: head(code, []), receivedBytes: 1_000) == .undecided)
    }

    @Test
    func verdict_whenTheAnswerIsEncoded_isUndecided() {
        let answer = head(416, [("Content-Range", "bytes */1000"), ("Content-Encoding", "gzip")])

        #expect(Probe.verdict(of: answer, receivedBytes: 1_000) == .undecided)
    }

    @Test
    func isApplicable_needsByteRangesAndNoContentEncoding() {
        #expect(Probe.isApplicable(to: head(200, [("Accept-Ranges", "bytes")])))
        #expect(Probe.isApplicable(to: head(200, [("accept-ranges", " none, Bytes ")])))
        #expect(Probe.isApplicable(to: head(200, [("Accept-Ranges", "bytes"), ("Content-Encoding", "identity")])))

        #expect(!Probe.isApplicable(to: head(200, [])))
        #expect(!Probe.isApplicable(to: head(200, [("Accept-Ranges", "none")])))
        #expect(!Probe.isApplicable(to: head(200, [("Accept-Ranges", "bytes"), ("Content-Encoding", "gzip")])))
    }
}

/// What the probe sends, and what it does when the server does not answer.
struct CompletenessProbeRunTests {

    private typealias Probe = Internals.CacheControl.CompletenessProbe

    private final class Recorder: Sendable {

        private struct State {
            var configurations: [RequestConfiguration] = []
            var cancelled = 0
            var readBodyInFull = 0
        }

        private let box = LockedValueBox(State())

        var configurations: [RequestConfiguration] { box.withLockedValue { $0.configurations } }

        /// How many of the requests were cancelled by whoever asked for them.
        var cancelled: Int { box.withLockedValue { $0.cancelled } }

        /// How many times the head came with the whole body, as `revalidationHead` returns it.
        var readBodyInFull: Int { box.withLockedValue { $0.readBodyInFull } }

        func append(_ configuration: RequestConfiguration) {
            box.withLockedValue { $0.configurations.append(configuration) }
        }

        func cancel() {
            box.withLockedValue { $0.cancelled += 1 }
        }

        func readInFull() {
            box.withLockedValue { $0.readBodyInFull += 1 }
        }
    }

    /// Answers like an executor that streams: the head first, then a body that never ends, which
    /// only stops when the request is cancelled.
    private struct ScriptedClient: RequestExecutingClient {

        let recorder: Recorder
        let answer: @Sendable () async throws -> Internals.ResponseHead

        func execute(
            configuration: RequestConfiguration,
            decompression: Internals.Decompression,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.Chunk>?)?,
            logger: Internals.TaskLogger?,
            transferControl: Internals.TransferControl?
        ) async throws -> SessionTask {
            recorder.append(configuration)

            let head = try await answer()
            let recorder = recorder
            let download = await Internals.DownloadBuffer(readingMode: configuration.readingMode)

            return SessionTask(
                seed: .init {
                    recorder.cancel()
                    download.close()
                },
                response: .init(
                    logger: logger,
                    uploadingBytes: .zero,
                    upload: .empty(),
                    decompressionDispatch: .skip,
                    readingMode: configuration.readingMode,
                    head: .constant(head),
                    download: download.stream
                )
            )
        }

        func revalidationHead(
            configuration: RequestConfiguration,
            logger: Internals.TaskLogger?,
            metrics: Internals.RequestMetricsCollector?
        ) async throws -> Internals.ResponseHead {
            recorder.append(configuration)
            recorder.readInFull()
            return try await answer()
        }
    }

    private struct Failure: Error {}

    private func head(_ code: UInt, _ headers: [(String, String)]) -> Internals.ResponseHead {
        .init(
            url: "https://example.com/resource",
            status: .init(code: code, reason: ""),
            version: .init(minor: 1, major: 1),
            headers: headers.map { .init(name: $0.0, value: $0.1) },
            isKeepAlive: true
        )
    }

    private func probe(
        recorder: Recorder,
        timeLimit: UInt64? = nil,
        configure: (inout RequestConfiguration) -> Void = { _ in },
        answer: @escaping @Sendable () async throws -> Internals.ResponseHead
    ) -> Probe {
        var configuration = RequestConfiguration()
        configure(&configuration)

        var probe = Probe(
            client: ScriptedClient(recorder: recorder, answer: answer),
            requestConfiguration: configuration,
            logger: nil
        )

        if let timeLimit {
            probe.timeLimitInNanoseconds = timeLimit
        }

        return probe
    }

    private var ranges: [(String, String)] { [("Accept-Ranges", "bytes")] }

    @Test
    func run_whenTheServerDoesNotAnswer_isUndecided() async {
        let recorder = Recorder()
        let probe = probe(recorder: recorder, timeLimit: 50_000_000) {
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return self.head(416, [("Content-Range", "bytes */10")])
        }

        #expect(await probe.run(response: head(200, ranges), receivedBytes: 10) == .undecided)
        #expect(recorder.configurations.count == 1)
    }

    /// A `200` with the whole resource (an `If-Range` that no longer matches) is answered by a body
    /// the probe has no use for. It has to stop at the head: `revalidationHead` returns the body too,
    /// and `.urlSession` collects all of it in memory first.
    @Test(arguments: [200, 206, 416])
    func run_readsTheHeadOnly_andCancelsTheRequestWithoutTakingTheBody(_ status: UInt) async {
        let recorder = Recorder()
        let probe = probe(recorder: recorder) { self.head(status, [("Content-Range", "bytes */10")]) }

        _ = await probe.run(response: head(200, ranges), receivedBytes: 10)

        #expect(recorder.configurations.count == 1)
        #expect(recorder.readBodyInFull == 0)
        #expect(recorder.cancelled == 1)
    }

    @Test
    func run_whenTheRequestFails_isUndecided() async {
        let recorder = Recorder()
        let probe = probe(recorder: recorder) { throw Failure() }

        #expect(await probe.run(response: head(200, ranges), receivedBytes: 10) == .undecided)
    }

    @Test
    func run_whenTheResponseCannotBeChecked_sendsNothing() async {
        let recorder = Recorder()
        let probe = probe(recorder: recorder) { self.head(416, [("Content-Range", "bytes */10")]) }

        #expect(await probe.run(response: head(200, []), receivedBytes: 10) == .undecided)
        #expect(recorder.configurations.isEmpty)
    }

    @Test
    func run_asksForTheNextByte_insteadOfWhateverTheCallerSet() async throws {
        let recorder = Recorder()
        let probe = probe(
            recorder: recorder,
            configure: {
                $0.headers.add(name: "Range", value: "bytes=0-1")
                $0.headers.add(name: "If-None-Match", value: "\"other\"")
                $0.headers.add(name: "If-Modified-Since", value: "yesterday")
                $0.headers.add(name: "Authorization", value: "Bearer token")
            },
            answer: { self.head(416, [("Content-Range", "bytes */10")]) }
        )

        let verdict = await probe.run(
            response: head(200, ranges + [("ETag", "\"strong\""), ("Last-Modified", "a date")]),
            receivedBytes: 10
        )

        let sent = try #require(recorder.configurations.first)

        #expect(verdict == .complete)
        #expect(sent.headers["Range"] == ["bytes=10-10"])
        #expect(sent.headers["If-Range"] == ["\"strong\""])
        #expect(sent.headers["If-None-Match"] == nil)
        #expect(sent.headers["If-Modified-Since"] == nil)
        #expect(sent.headers["Authorization"] == ["Bearer token"])
    }

    /// The response being cached set a cookie after the request had gone out, so the header the
    /// request started with is stale by the time the probe is sent.
    @Test
    func run_sendsTheCookiesTheJarHoldsNow_whenTheJarOwnsTheHeader() async throws {
        let storage = Internals.CookieStorage()
        let target = try #require(URL(string: "https://example.com/resource"))
        storage.store(setCookieValues: ["old=1"], for: target)

        let recorder = Recorder()
        let probe = probe(
            recorder: recorder,
            configure: {
                $0.exactURL = "https://example.com/resource"
                $0.headers.add(name: "Cookie", value: "old=1")
                $0.cookies = .init(storage: storage, managesHeader: true, initialCookieHeader: "old=1")
            },
            answer: { self.head(416, [("Content-Range", "bytes */10")]) }
        )

        // The response to the request itself sets a cookie.
        storage.store(setCookieValues: ["session=2"], for: target)

        _ = await probe.run(response: head(200, ranges), receivedBytes: 10)

        let sent = try #require(recorder.configurations.first)
        #expect(sent.headers["Cookie"] == ["old=1; session=2"])
    }

    /// A `Cookie` header the caller set is theirs, on the probe as on every other request.
    @Test
    func run_keepsTheCookieTheCallerSet() async throws {
        let storage = Internals.CookieStorage()
        let target = try #require(URL(string: "https://example.com/resource"))
        storage.store(setCookieValues: ["session=2"], for: target)

        let recorder = Recorder()
        let probe = probe(
            recorder: recorder,
            configure: {
                $0.exactURL = "https://example.com/resource"
                $0.headers.add(name: "Cookie", value: "mine=1")
                $0.cookies = .init(storage: storage, managesHeader: false, initialCookieHeader: "mine=1")
            },
            answer: { self.head(416, [("Content-Range", "bytes */10")]) }
        )

        _ = await probe.run(response: head(200, ranges), receivedBytes: 10)

        let sent = try #require(recorder.configurations.first)
        #expect(sent.headers["Cookie"] == ["mine=1"])
    }

    @Test
    func run_whenTheEntityTagIsWeak_sendsTheLastModifiedInstead() async throws {
        let recorder = Recorder()
        let probe = probe(recorder: recorder) { self.head(206, [("Content-Range", "bytes 10-10/20")]) }

        let verdict = await probe.run(
            response: head(200, ranges + [("ETag", "W/\"weak\""), ("Last-Modified", " a date ")]),
            receivedBytes: 10
        )

        #expect(verdict == .truncated)
        #expect(recorder.configurations.first?.headers["If-Range"] == ["a date"])
    }

    @Test
    func run_whenThereIsNoValidator_sendsNoIfRange() async throws {
        let recorder = Recorder()
        let probe = probe(recorder: recorder) { self.head(416, [("Content-Range", "bytes */10")]) }

        #expect(await probe.run(response: head(200, ranges), receivedBytes: 10) == .complete)
        #expect(recorder.configurations.first?.headers["If-Range"] == nil)
    }

    @Test
    func verdict_whenAPartialAnswerSaysNothingOfTheRange_isUndecided() {
        #expect(Probe.verdict(of: head(206, []), receivedBytes: 10) == .undecided)
        #expect(Probe.verdict(of: head(206, [("Content-Range", "items 10-10/20")]), receivedBytes: 10) == .undecided)
    }

    @Test
    func verdict_whenTheUnsatisfiedRangeIsNotInBytes_isUndecided() {
        #expect(Probe.verdict(of: head(416, [("Content-Range", "items */10")]), receivedBytes: 10) == .undecided)
        #expect(Probe.verdict(of: head(416, [("Content-Range", "bytes")]), receivedBytes: 10) == .undecided)
    }
}
