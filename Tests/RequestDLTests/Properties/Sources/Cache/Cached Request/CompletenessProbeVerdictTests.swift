//
// See LICENSE for this package's licensing information.
//

@_spi(Testing) import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

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

        private let box = LockedValueBox<[RequestConfiguration]>([])

        var configurations: [RequestConfiguration] { box.withLockedValue { $0 } }

        func append(_ configuration: RequestConfiguration) {
            box.withLockedValue { $0.append(configuration) }
        }
    }

    private struct ScriptedClient: RequestExecutingClient {

        let recorder: Recorder
        let answer: @Sendable () async throws -> Internals.ResponseHead

        func execute(
            configuration: RequestConfiguration,
            decompression: Internals.Decompression,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?,
            transferControl: Internals.TransferControl?
        ) async throws -> SessionTask {
            fatalError("The probe only asks for a head")
        }

        func revalidationHead(
            configuration: RequestConfiguration,
            logger: Internals.TaskLogger?,
            metrics: Internals.RequestMetricsCollector?
        ) async throws -> Internals.ResponseHead {
            recorder.append(configuration)
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
