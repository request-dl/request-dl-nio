//
// See LICENSE for this package's licensing information.
//

@_spi(Testing) import RequestDLInternals
import Testing

@testable import RequestDL

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
