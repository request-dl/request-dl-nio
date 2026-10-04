//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct IETFResumableUploadDialectTests {

    private typealias Fixtures = ResumableUploadDialectFixtures

    private let dialect = IETFResumableUploadDialect()

    @Test
    func requiresKnownLength_isFalse() {
        #expect(!dialect.requiresKnownLength)
    }

    // MARK: - Creation

    @Test
    func creation_isTheRequestThatWasWrittenWithoutItsBody() async {
        // Given
        let request = await Fixtures.request(method: "PUT")

        // When
        let creation = dialect.creation(for: request, length: nil)

        // Then: same method, same URL, and the headers that describe what is being created.
        #expect(creation.method == "PUT")
        #expect(creation.url == "https://example.com/files/report.bin?folder=a")
        #expect(creation.headers.first(name: "Content-Type") == "application/json")
        #expect(creation.headers.first(name: "Content-Encoding") == "gzip")
        #expect(creation.headers.first(name: "Upload-Complete") == "?0")
        #expect(creation.headers.first(name: "Upload-Length") == nil)
    }

    @Test
    func creation_whenLengthIsKnown_declaresIt() async {
        // When
        let creation = dialect.creation(for: await Fixtures.request(), length: 4_096)

        // Then
        #expect(creation.headers.first(name: "Upload-Length") == "4096")
    }

    // MARK: - Sending

    @Test
    func append_completesTheUploadWithThePartialUploadType() async {
        // When
        let append = dialect.append(to: Fixtures.resource, from: 10, like: await Fixtures.request())

        // Then
        #expect(append.headers.first(name: "Content-Type") == "application/partial-upload")
        #expect(append.headers.first(name: "Upload-Complete") == "?1")
        #expect(append.headers.first(name: "Upload-Offset") == "10")
    }

    // MARK: - What the server says

    @Test(arguments: [("?1", true), ("?0", false), ("1", false), ("", false)])
    func report_readsWhetherTheUploadIsComplete(_ value: String, _ expected: Bool) throws {
        // Given
        let head = Fixtures.head(204, [("Upload-Offset", "10"), ("Upload-Complete", value)])

        // Then
        #expect(try dialect.report(from: head).isComplete == expected)
    }

    @Test
    func outcome_whenTheServerAnswersTheUploadRequest_isFinished() {
        for status: UInt in [200, 201, 204] {
            #expect(dialect.outcome(of: Fixtures.head(status), offset: 0, length: nil) == .finished)
        }
    }

    @Test
    func outcome_whenTheOffsetDisagrees_isTheServersOffset() {
        // Given
        let head = Fixtures.head(409, [("Upload-Offset", "512")])

        // Then
        #expect(dialect.outcome(of: head, offset: 1_024, length: 2_048) == .conflict(offset: 512))
        #expect(dialect.outcome(of: Fixtures.head(409), offset: 1_024, length: 2_048) == .conflict(offset: nil))
    }

    @Test
    func completionResponse_isNone() {
        // The response to the request that completed the upload is the application's.
        #expect(dialect.completionResponse(from: Fixtures.head(204, [("Upload-Offset", "10")])) == nil)
    }
}
