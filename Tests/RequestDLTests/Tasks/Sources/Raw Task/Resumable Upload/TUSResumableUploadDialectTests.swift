//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct TUSResumableUploadDialectTests {

    private typealias Fixtures = ResumableUploadDialectFixtures

    private let dialect = TUSResumableUploadDialect()

    @Test
    func requiresKnownLength_isTrue() {
        #expect(dialect.requiresKnownLength)
    }

    // MARK: - Creation

    @Test
    func creation_isAPostToTheURLOfTheRequestWrittenWhateverItsMethod() async {
        // Given
        let request = await Fixtures.request(method: "PUT")

        // When
        let creation = dialect.creation(for: request, length: 4_096)

        // Then
        #expect(creation.method == "POST")
        #expect(creation.url == "https://example.com/files/report.bin?folder=a")
        #expect(creation.headers.first(name: "Tus-Resumable") == "1.0.0")
        #expect(creation.headers.first(name: "Upload-Length") == "4096")
    }

    @Test
    func creation_carriesTheContentTypeAsTheFileTypeMetadata() async throws {
        // When
        let creation = dialect.creation(for: await Fixtures.request(), length: 5)

        // Then: tus has no other place for it, and the header itself is not sent.
        let expected = Data("application/json".utf8).base64EncodedString()
        #expect(creation.headers.first(name: "Upload-Metadata") == "filetype \(expected)")
        #expect(creation.headers.first(name: "Content-Type") == nil)
    }

    @Test
    func creation_whenThereIsNoContentType_hasNoMetadata() async {
        // Given
        var request = await Fixtures.request()
        request.headers.remove(name: "Content-Type")

        // When
        let creation = dialect.creation(for: request, length: 5)

        // Then
        #expect(creation.headers.first(name: "Upload-Metadata") == nil)
    }

    // MARK: - Every request

    @Test
    func everyRequest_statesTheVersion() async throws {
        // Given
        let request = await Fixtures.request()
        let requests = [
            dialect.creation(for: request, length: 5),
            dialect.offsetQuery(for: Fixtures.resource, like: request),
            dialect.append(to: Fixtures.resource, from: 0, like: request),
            try #require(dialect.cancellation(of: Fixtures.resource, like: request)),
        ]

        // Then
        for request in requests {
            #expect(request.headers.first(name: "Tus-Resumable") == "1.0.0")
        }
    }

    // MARK: - Sending

    @Test
    func append_usesTheOffsetOctetStreamType_andNeverSaysItCompletes() async {
        // When
        let append = dialect.append(to: Fixtures.resource, from: 10, like: await Fixtures.request())

        // Then
        #expect(append.headers.first(name: "Content-Type") == "application/offset+octet-stream")
        #expect(append.headers.first(name: "Upload-Complete") == nil)
    }

    // MARK: - What the server says

    @Test
    func report_isCompleteWhenTheOffsetReachesTheLength() throws {
        #expect(
            try dialect.report(from: Fixtures.head(200, [("Upload-Offset", "10"), ("Upload-Length", "10")])).isComplete
        )
        #expect(
            try !dialect.report(from: Fixtures.head(200, [("Upload-Offset", "9"), ("Upload-Length", "10")])).isComplete
        )
        #expect(try !dialect.report(from: Fixtures.head(200, [("Upload-Offset", "9")])).isComplete)
    }

    @Test
    func outcome_isFinishedWhenTheServerHoldsTheWholeBody() {
        // Given
        let head = Fixtures.head(204, [("Upload-Offset", "100")])

        // Then
        #expect(dialect.outcome(of: head, offset: 40, length: 100) == .finished)
    }

    @Test
    func outcome_isPartialWhenTheServerHoldsLess() {
        // Given
        let head = Fixtures.head(204, [("Upload-Offset", "70")])

        // Then
        #expect(dialect.outcome(of: head, offset: 40, length: 100) == .partial(offset: 70))
    }

    @Test
    func outcome_whenTheServerDoesNotSayWhatItHolds_isOther() {
        #expect(dialect.outcome(of: Fixtures.head(204), offset: 40, length: 100) == .other)
    }

    @Test
    func outcome_whenForbidden_isGone() {
        // tus answers 403 for an upload it will not take anymore, as well as 404 and 410.
        #expect(dialect.outcome(of: Fixtures.head(403), offset: 0, length: 10) == .gone)
    }

    @Test
    func outcome_whenTheOffsetDisagrees_leavesTheOffsetToBeAsked() {
        #expect(dialect.outcome(of: Fixtures.head(409), offset: 5, length: 10) == .conflict(offset: nil))
    }
}
