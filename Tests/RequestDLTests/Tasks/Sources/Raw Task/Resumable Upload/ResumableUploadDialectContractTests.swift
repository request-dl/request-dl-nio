//
// See LICENSE for this package's licensing information.
//

import Testing

@_spi(Private) @testable import RequestDL

/// What holds for every dialect, since it is what a driver that doesn't know which one it has
/// relies on.
struct ResumableUploadDialectContractTests {

    private typealias Fixtures = ResumableUploadDialectFixtures

    // MARK: - Creation

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func creation_hasNoBody(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        let request = await Fixtures.request()

        // When
        let creation = kind.dialect.creation(for: request, length: 5)

        // Then: the body is what the requests that follow carry.
        #expect(creation.body == nil)
        #expect(creation.headers.first(name: "Content-Length") == nil)
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func creation_keepsWhatTheCallerSetUpForTheRequest(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        let request = await Fixtures.request()

        // When
        let creation = kind.dialect.creation(for: request, length: 5)

        // Then
        #expect(creation.headers.first(name: "Authorization") == "Bearer token")
        #expect(creation.headers.first(name: "Cookie") == "session=1")
        #expect(creation.url == request.url)
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func creation_isNeverServedFromTheCache(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        var request = await Fixtures.request(method: "GET")
        request.cachePolicy = .all
        request.cacheStrategy = .returnCachedDataElseLoad

        // When
        let creation = kind.dialect.creation(for: request, length: 5)

        // Then
        #expect(creation.cachePolicy.isEmpty)
        #expect(creation.cacheStrategy == .ignoreCachedData)
    }

    // MARK: - The upload's URL

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func resource_whenLocationIsAbsolute_isThatURL(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        let request = await Fixtures.request()
        let head = Fixtures.head(201, [("Location", "https://uploads.example.net/u/9")])

        // When
        let resource = try kind.dialect.resource(from: head, createdFor: request)

        // Then
        #expect(resource.url == "https://uploads.example.net/u/9")
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func resource_whenLocationIsRelative_isResolvedAgainstTheRequest(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        let request = await Fixtures.request()
        let head = Fixtures.head(201, [("Location", "/uploads/42")])

        // When
        let resource = try kind.dialect.resource(from: head, createdFor: request)

        // Then
        #expect(resource.url == "https://example.com/uploads/42")
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func resource_whenThereIsNoLocation_throws(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        let request = await Fixtures.request()

        // Then
        #expect(throws: ResumableUploadDialectError(reason: .missingLocation)) {
            try kind.dialect.resource(from: Fixtures.head(201), createdFor: request)
        }
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func resource_whenCreationWasRejected_throwsWithTheStatus(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        let request = await Fixtures.request()
        let head = Fixtures.head(403, [("Location", "/uploads/42")])

        // Then
        #expect(throws: ResumableUploadDialectError(reason: .creationRejected(status: 403))) {
            try kind.dialect.resource(from: head, createdFor: request)
        }
    }

    // MARK: - Requests about the upload

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func offsetQuery_isAHeadOfTheUploadWithoutWhatDescribedTheBody(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        let request = await Fixtures.request()

        // When
        let query = kind.dialect.offsetQuery(for: Fixtures.resource, like: request)

        // Then
        #expect(query.method == "HEAD")
        #expect(query.url == Fixtures.resource.url)
        #expect(query.body == nil)
        #expect(query.headers.first(name: "Authorization") == "Bearer token")
        #expect(query.headers.first(name: "Content-Type") == nil)
        #expect(query.headers.first(name: "Content-Encoding") == nil)
        #expect(query.headers.first(name: "Content-Length") == nil)
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func append_isAPatchFromTheOffsetWithTheBodyLeftToTheCaller(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        let request = await Fixtures.request()

        // When
        let append = kind.dialect.append(to: Fixtures.resource, from: 1_024, like: request)

        // Then
        #expect(append.method == "PATCH")
        #expect(append.url == Fixtures.resource.url)
        #expect(append.body == nil)
        #expect(append.headers.first(name: "Upload-Offset") == "1024")
        #expect(append.headers.first(name: "Authorization") == "Bearer token")
        #expect(append.headers.first(name: "Content-Encoding") == nil)
        #expect(append.headers.first(name: "Content-Length") == nil)
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func cancellation_isADeleteOfTheUpload(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        let request = await Fixtures.request()

        // When
        let cancellation = try #require(kind.dialect.cancellation(of: Fixtures.resource, like: request))

        // Then
        #expect(cancellation.method == "DELETE")
        #expect(cancellation.url == Fixtures.resource.url)
        #expect(cancellation.body == nil)
        #expect(cancellation.headers.first(name: "Authorization") == "Bearer token")
    }

    // MARK: - What the server says

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func report_readsTheOffset(_ kind: ResumableUploadDialectKind) throws {
        // Given
        let head = Fixtures.head(204, [("Upload-Offset", "700"), ("Upload-Length", "1000")])

        // When
        let report = try kind.dialect.report(from: head)

        // Then
        #expect(report.offset == 700)
        #expect(report.length == 1_000)
        #expect(!report.isComplete)
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func report_whenOffsetIsMissingOrInvalid_throws(_ kind: ResumableUploadDialectKind) {
        for headers in [[], [("Upload-Offset", "-1")], [("Upload-Offset", "many")], [("Upload-Offset", "")]] {
            #expect(throws: ResumableUploadDialectError(reason: .missingOffset)) {
                try kind.dialect.report(from: Fixtures.head(204, headers))
            }
        }
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func report_whenTheServerRefuses_throwsWithTheStatus(_ kind: ResumableUploadDialectKind) {
        #expect(throws: ResumableUploadDialectError(reason: .offsetRejected(status: 404))) {
            try kind.dialect.report(from: Fixtures.head(404, [("Upload-Offset", "0")]))
        }
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func outcome_whenTheServerNoLongerHasTheUpload_isGone(_ kind: ResumableUploadDialectKind) {
        for status: UInt in [404, 410] {
            #expect(kind.dialect.outcome(of: Fixtures.head(status), offset: 0, length: 10) == .gone)
        }
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func outcome_whenTheOffsetDisagrees_isAConflict(_ kind: ResumableUploadDialectKind) {
        #expect(
            {
                if case .conflict = kind.dialect.outcome(of: Fixtures.head(409), offset: 5, length: 10) {
                    return true
                }
                return false
            }()
        )
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func outcome_whenTheServerFails_isOther(_ kind: ResumableUploadDialectKind) {
        for status: UInt in [400, 401, 500, 503] {
            #expect(kind.dialect.outcome(of: Fixtures.head(status), offset: 0, length: 10) == .other)
        }
    }
}
