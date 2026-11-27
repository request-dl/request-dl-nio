//
// See LICENSE for this package's licensing information.
//

import Testing

@_spi(Private) @testable import RequestDL
@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import struct FoundationEssentials.URL
#else
import struct Foundation.URL
#endif

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

    /// A creation that was redirected is answered by another URL than the one it was sent to, and a
    /// relative `Location` is relative to the one that answered.
    @Test(arguments: ResumableUploadDialectKind.allCases)
    func resource_whenLocationIsRelative_isResolvedAgainstTheURLThatAnswered(
        _ kind: ResumableUploadDialectKind
    ) async throws {
        // Given
        let request = await Fixtures.request()
        let head = Fixtures.head(
            201,
            [("Location", "created/42")],
            url: URL(string: "https://cdn.example.net/v2/files/")
        )

        // When
        let resource = try kind.dialect.resource(from: head, createdFor: request)

        // Then
        #expect(resource.url == "https://cdn.example.net/v2/files/created/42")
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func resource_whenTheURLThatAnsweredIsUnknown_isResolvedAgainstTheRequest(
        _ kind: ResumableUploadDialectKind
    ) async throws {
        // Given
        let request = await Fixtures.request()
        let head = Fixtures.head(201, [("Location", "/uploads/42")], url: nil)

        // When
        let resource = try kind.dialect.resource(from: head, createdFor: request)

        // Then
        #expect(resource.url == "https://example.com/uploads/42")
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func resource_whenTheRedirectedCreationLeavesHTTPS_isNotAcceptedOverHTTP(
        _ kind: ResumableUploadDialectKind
    ) async throws {
        // Given: the request went over `https`, and so does not take the rest of the upload to `http`
        // whichever URL answered.
        let request = await Fixtures.request()
        let head = Fixtures.head(
            201,
            [("Location", "/uploads/42")],
            url: URL(string: "http://cdn.example.net/files")
        )

        // Then
        #expect(throws: ResumableUploadDialectError.self) {
            try kind.dialect.resource(from: head, createdFor: request)
        }
    }

    @Test(
        arguments: ResumableUploadDialectKind.allCases,
        ["https://example.com/uploads/42/", "https://example.com/u/1/?t=2"]
    )
    func requestsToTheUpload_keepTheURLExactlyAsTheServerSaidIt(
        _ kind: ResumableUploadDialectKind,
        _ url: String
    ) async throws {
        // Given: a server whose upload URL ends in a slash, which is a different resource than the
        // one without it.
        let request = await Fixtures.request()
        let resource = UploadResource(url: url)
        let dialect = kind.dialect

        // Then
        #expect(dialect.offsetQuery(for: resource, like: request).url == url)
        #expect(dialect.append(to: resource, from: 5, like: request).url == url)
        #expect(dialect.cancellation(of: resource, like: request)?.url == url)
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func resource_whenLocationEndsInASlash_keepsIt(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        let request = await Fixtures.request()
        let head = Fixtures.head(201, [("Location", "https://example.com/files/abc/")])

        // When
        let resource = try kind.dialect.resource(from: head, createdFor: request)
        let append = kind.dialect.append(to: resource, from: 0, like: request)

        // Then
        #expect(append.url == "https://example.com/files/abc/")
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

    @Test(
        arguments: ResumableUploadDialectKind.allCases,
        ["ftp://uploads.example.com/u/9", "file:///etc/hosts", "mailto:a@example.com"]
    )
    func resource_whenLocationIsNotHTTP_throws(_ kind: ResumableUploadDialectKind, _ location: String) async throws {
        // Given
        let request = await Fixtures.request()
        let head = Fixtures.head(201, [("Location", location)])

        // Then
        #expect(throws: ResumableUploadDialectError(reason: .missingLocation)) {
            try kind.dialect.resource(from: head, createdFor: request)
        }
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func resource_whenLocationCannotBeRead_throws(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        let request = await Fixtures.request()
        let head = Fixtures.head(201, [("Location", "http://[not-a-host/u/1")])

        // Then
        #expect(throws: ResumableUploadDialectError(reason: .missingLocation)) {
            try kind.dialect.resource(from: head, createdFor: request)
        }
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func resource_whenLocationDowngradesHTTPSToHTTP_throws(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        let request = await Fixtures.request()
        let head = Fixtures.head(201, [("Location", "http://example.com/uploads/42")])

        // Then
        #expect(throws: ResumableUploadDialectError(reason: .missingLocation)) {
            try kind.dialect.resource(from: head, createdFor: request)
        }
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func resource_whenTheRequestIsHTTP_acceptsHTTPAndHTTPS(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        var request = await Fixtures.request()
        request.baseURL = "http://example.com"

        // When
        let plain = try kind.dialect.resource(
            from: Fixtures.head(201, [("Location", "http://example.com/u/1")]),
            createdFor: request
        )
        let secure = try kind.dialect.resource(
            from: Fixtures.head(201, [("Location", "https://example.com/u/1")]),
            createdFor: request
        )

        // Then
        #expect(plain.url == "http://example.com/u/1")
        #expect(secure.url == "https://example.com/u/1")
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
    func outcome_whenTheServerRefuses_isOther(_ kind: ResumableUploadDialectKind) {
        for status: UInt in [400, 401, 413, 422] {
            #expect(kind.dialect.outcome(of: Fixtures.head(status), offset: 0, length: 10) == .other)
        }
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func outcome_whenTheServerSaysNotNow_isTransient(_ kind: ResumableUploadDialectKind) {
        for status: UInt in [408, 425, 429, 500, 502, 503, 504, 599] {
            #expect(kind.dialect.outcome(of: Fixtures.head(status), offset: 0, length: 10) == .transient)
        }
    }

    // MARK: - Credentials

    private static let otherOrigin = UploadResource(url: "https://uploads.example.net/u/9")

    private func requests(
        _ kind: ResumableUploadDialectKind,
        to resource: UploadResource,
        like request: RequestConfiguration
    ) throws -> [RequestConfiguration] {
        let dialect = kind.dialect

        return [
            dialect.offsetQuery(for: resource, like: request),
            dialect.append(to: resource, from: 1_024, like: request),
            try #require(dialect.cancellation(of: resource, like: request)),
        ]
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func requestsToAnotherOrigin_doNotCarryTheCallersCredentials(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        var request = await Fixtures.request()
        request.headers.set(name: "Proxy-Authorization", value: "Basic abc")
        request.headers.set(name: "Origin", value: "https://example.com")
        request.headers.set(name: "Accept", value: "application/json")

        // When
        let derived = try requests(kind, to: Self.otherOrigin, like: request)

        // Then
        for query in derived {
            #expect(query.url == Self.otherOrigin.url)
            #expect(query.headers.first(name: "Authorization") == nil)
            #expect(query.headers.first(name: "Cookie") == nil)
            #expect(query.headers.first(name: "Proxy-Authorization") == nil)
            #expect(query.headers.first(name: "Origin") == nil)
            #expect(query.headers.first(name: "Accept") == "application/json")
        }
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func requestsToAURLThatCannotBeRead_doNotCarryTheCallersCredentials(_ kind: ResumableUploadDialectKind) async throws
    {
        // Given
        let request = await Fixtures.request()

        // When
        let derived = try requests(kind, to: UploadResource(url: "not a url"), like: request)

        // Then
        for query in derived {
            #expect(query.headers.first(name: "Authorization") == nil)
            #expect(query.headers.first(name: "Cookie") == nil)
        }
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func requestsToAnotherOrigin_keepTheCallersCredentials_whenTheCallerAsksForIt(
        _ kind: ResumableUploadDialectKind
    ) async throws {
        // Given
        var request = await Fixtures.request()
        request.forwardsCredentialsToOtherOrigins = true

        // When
        let derived = try requests(kind, to: Self.otherOrigin, like: request)

        // Then
        for query in derived {
            #expect(query.url == Self.otherOrigin.url)
            #expect(query.headers.first(name: "Authorization") == "Bearer token")
            #expect(query.headers.first(name: "Cookie") == "session=1")
        }
    }

    @Test(
        arguments: ResumableUploadDialectKind.allCases,
        [
            "https://example.com/uploads/42",
            "https://EXAMPLE.com:443/uploads/42",
        ]
    )
    func requestsToTheSameOrigin_keepTheCallersCredentials(
        _ kind: ResumableUploadDialectKind,
        _ url: String
    ) async throws {
        // Given
        let request = await Fixtures.request()

        // When
        let derived = try requests(kind, to: UploadResource(url: url), like: request)

        // Then
        for query in derived {
            #expect(query.headers.first(name: "Authorization") == "Bearer token")
            #expect(query.headers.first(name: "Cookie") == "session=1")
        }
    }

    @Test(
        arguments: ResumableUploadDialectKind.allCases,
        [
            "https://example.com:8443/u/1",
            "https://sub.example.com/u/1",
            "http://example.com/u/1",
        ]
    )
    func requestsToADifferentSchemeHostOrPort_doNotCarryTheCallersCredentials(
        _ kind: ResumableUploadDialectKind,
        _ url: String
    ) async throws {
        // Given
        let request = await Fixtures.request()

        // When
        let derived = try requests(kind, to: UploadResource(url: url), like: request)

        // Then
        for query in derived {
            #expect(query.headers.first(name: "Authorization") == nil)
            #expect(query.headers.first(name: "Cookie") == nil)
        }
    }

    @Test(arguments: ResumableUploadDialectKind.allCases, [false, true])
    func requestsToAnotherOrigin_doNotCarryAnExplicitHost(
        _ kind: ResumableUploadDialectKind,
        _ forwards: Bool
    ) async throws {
        // Given: `Host` names the virtual host of the origin the caller wrote the request for; at
        // another origin it routes the request to whatever answers to that name there, so it stays
        // behind even for a caller that forwards its credentials.
        var request = await Fixtures.request()
        request.headers.set(name: "Host", value: "internal.example.com")
        request.forwardsCredentialsToOtherOrigins = forwards

        // When
        let derived = try requests(kind, to: Self.otherOrigin, like: request)

        // Then
        for query in derived {
            #expect(query.headers.first(name: "Host") == nil)
        }
    }

    @Test(arguments: ResumableUploadDialectKind.allCases)
    func requestsToTheSameOrigin_keepAnExplicitHost(_ kind: ResumableUploadDialectKind) async throws {
        // Given
        var request = await Fixtures.request()
        request.headers.set(name: "Host", value: "internal.example.com")

        // When
        let derived = try requests(kind, to: Fixtures.resource, like: request)

        // Then
        for query in derived {
            #expect(query.headers.first(name: "Host") == "internal.example.com")
        }
    }

    @Test
    func theHeadersLeftBehindAtAnotherOrigin_areTheOnesARedirectLeavesBehind() async throws {
        // Given: every header a redirect to another origin strips, set on the request.
        var request = await Fixtures.request()

        for name in Internals.RedirectSanitizer.crossOriginHeaders {
            request.headers.set(name: name, value: "value")
        }

        // When
        let derived = try requests(.ietf, to: Self.otherOrigin, like: request)

        // Then
        for query in derived {
            for name in Internals.RedirectSanitizer.crossOriginHeaders {
                #expect(query.headers.first(name: name) == nil, "\(name) followed the upload to another origin")
            }
        }
    }
}
