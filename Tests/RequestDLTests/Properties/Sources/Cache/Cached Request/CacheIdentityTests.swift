//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

import class Foundation.FileManager

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

/// A request that declares a ``CacheIdentity`` is told apart from the others by it, and not by
/// the credentials it sends.
///
/// The server answers with the `output` the test gave it, so what a request got shows whether it
/// was served the stored response (the first output) or went to the network (its own).
extension CachedRequestTests {

    private static let identityField = "x-request-dl-identity"

    private func identityRequest(
        _ testState: TestState,
        vary: String? = nil,
        requestHeaders: [(String, String)] = [],
        identity: String? = nil,
        output: String
    ) async throws -> String {
        var headers = makeHeaders(maxAgeSeconds: 3_600)

        if let vary {
            headers.append(("Vary", vary))
        }

        let result = try await performCacheRequest(
            testState: testState,
            headers: headers,
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: requestHeaders,
            identity: identity,
            output: output
        )

        await testState.dataCache.waitUntilIdle()
        return try responseText(result)
    }

    private func storedRecord(_ testState: TestState) async throws -> [String: String] {
        let cacheKey = "https://localhost:8888" + testState.uri

        return try #require(
            await testState.dataCache.getCachedData(forKey: cacheKey, policy: .all)?.cachedResponse.varyRequestHeaders
        )
    }

    // MARK: - Serving

    /// The point of the property: the token is refreshed, the account is the same.
    @Test
    func identity_whenTheAuthorizationIsRotated_servesTheSameIdentity() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer token-1")],
            identity: "user-1",
            output: "first"
        )

        let again = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer token-2")],
            identity: "user-1",
            output: "second"
        )

        #expect(again == "first")
    }

    @Test
    func identity_whenTheCookieIsReissued_servesTheSameIdentity() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(
            testState,
            requestHeaders: [("Cookie", "session=a")],
            identity: "user-1",
            output: "first"
        )

        let again = try await identityRequest(
            testState,
            requestHeaders: [("Cookie", "session=b; analytics=1")],
            identity: "user-1",
            output: "second"
        )

        #expect(again == "first")
    }

    @Test
    func identity_whenItDiffers_doesNotServeTheStoredResponse() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer shared-token")],
            identity: "user-1",
            output: "first"
        )

        // The same credential does not make it the same account: the identity is what counts.
        let other = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer shared-token")],
            identity: "user-2",
            output: "second"
        )

        #expect(other == "second")
    }

    @Test
    func identity_whenTheStoredResponseHasNone_doesNotServeItToARequestWithOne() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // A response stored for credentials, with no identity: whose it is cannot be told.
        _ = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer token-1")],
            output: "first"
        )

        let withIdentity = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer token-1")],
            identity: "user-1",
            output: "second"
        )

        #expect(withIdentity == "second")
    }

    @Test
    func identity_whenTheStoredResponseHasOne_doesNotServeItToARequestWithNone() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer token-1")],
            identity: "user-1",
            output: "first"
        )

        // Not even with the credential it was stored with.
        let withoutIdentity = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer token-1")],
            output: "second"
        )

        #expect(withoutIdentity == "second")
    }

    /// A request with no credentials and no identity stored it: it is public, and is served to
    /// everyone, an identity included.
    @Test
    func identity_whenTheStoredResponseIsPublic_servesItToARequestWithOne() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(testState, output: "first")

        let withIdentity = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer token-1")],
            identity: "user-1",
            output: "second"
        )

        #expect(withIdentity == "first")
    }

    @Test
    func identity_whenItIsTheSameAfterTrimmingWhitespace_isTheSameAccount() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer token-1")],
            identity: "user-1",
            output: "first"
        )

        let again = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer token-2")],
            identity: "  user-1\n",
            output: "second"
        )

        #expect(again == "first")
    }

    // MARK: - Vary

    /// The identity stands in for the credential headers a response varies on: the token that
    /// rotates is exactly what `Vary: Authorization` would tell apart.
    @Test
    func identity_whenTheResponseVariesOnAuthorization_servesTheSameIdentityAcrossATokenRefresh() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(
            testState,
            vary: "Authorization",
            requestHeaders: [("Authorization", "Bearer token-1")],
            identity: "user-1",
            output: "first"
        )

        let sameIdentity = try await identityRequest(
            testState,
            vary: "Authorization",
            requestHeaders: [("Authorization", "Bearer token-2")],
            identity: "user-1",
            output: "second"
        )

        #expect(sameIdentity == "first")
    }

    @Test
    func identity_whenTheResponseVariesOnCookie_servesTheSameIdentityAcrossAReissuedCookie() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(
            testState,
            vary: "Cookie",
            requestHeaders: [("Cookie", "session=a")],
            identity: "user-1",
            output: "first"
        )

        let sameIdentity = try await identityRequest(
            testState,
            vary: "Cookie",
            requestHeaders: [("Cookie", "session=b")],
            identity: "user-1",
            output: "second"
        )

        #expect(sameIdentity == "first")
    }

    @Test
    func identity_whenTheResponseVariesOnAuthorization_stillSeparatesIdentities() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(
            testState,
            vary: "Authorization",
            requestHeaders: [("Authorization", "Bearer token-1")],
            identity: "user-1",
            output: "first"
        )

        let otherIdentity = try await identityRequest(
            testState,
            vary: "Authorization",
            requestHeaders: [("Authorization", "Bearer token-1")],
            identity: "user-2",
            output: "second"
        )

        #expect(otherIdentity == "second")
    }

    /// Only the credential fields are stood in for: the others are compared as they always were.
    @Test
    func identity_whenTheResponseVariesOnAnotherField_stillComparesIt() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(
            testState,
            vary: "Authorization, Accept-Language",
            requestHeaders: [("Authorization", "Bearer token-1"), ("Accept-Language", "pt-BR")],
            identity: "user-1",
            output: "first"
        )

        let sameLanguage = try await identityRequest(
            testState,
            vary: "Authorization, Accept-Language",
            requestHeaders: [("Authorization", "Bearer token-2"), ("Accept-Language", "pt-BR")],
            identity: "user-1",
            output: "second"
        )

        #expect(sameLanguage == "first")

        let otherLanguage = try await identityRequest(
            testState,
            vary: "Authorization, Accept-Language",
            requestHeaders: [("Authorization", "Bearer token-2"), ("Accept-Language", "en")],
            identity: "user-1",
            output: "third"
        )

        // The server queues what a test gives it, and the hit above left "second" unread.
        #expect(otherLanguage != "first")
    }

    /// A public response that varies on `Authorization` was stored for a request that sent none:
    /// the identity does not say what the server would have answered to one that does.
    @Test
    func identity_whenAPublicResponseVariesOnAuthorization_doesNotServeItToARequestThatSendsOne() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(testState, vary: "Authorization", output: "first")

        let withAuthorization = try await identityRequest(
            testState,
            vary: "Authorization",
            requestHeaders: [("Authorization", "Bearer token-1")],
            identity: "user-1",
            output: "second"
        )

        #expect(withAuthorization == "second")
    }

    // MARK: - Empty identity

    /// An identity that is nothing is not one: the request is cached by its credentials.
    @Test(arguments: ["", "   ", "\n\t "])
    func identity_whenItIsEmpty_cachesByTheCredentialsLikeARequestWithNone(identity: String) async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer alice-token")],
            identity: identity,
            output: "first"
        )

        let record = try await storedRecord(testState)
        #expect(record[Self.identityField] == nil)
        #expect(Set(record.keys) == ["authorization", "cookie", "proxy-authorization"])

        let sameCredential = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer alice-token")],
            identity: identity,
            output: "second"
        )

        #expect(sameCredential == "first")

        // Two empty identities are not "the same account": another credential misses.
        let otherCredential = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer bob-token")],
            identity: identity,
            output: "third"
        )

        #expect(otherCredential != "first")
    }

    // MARK: - What is stored

    @Test
    func identity_recordsOneDigestAndNoCredential() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(
            testState,
            vary: "Authorization, Accept-Language",
            requestHeaders: [
                ("Authorization", "Bearer alice-token"),
                ("Cookie", "session=alice-cookie; theme=dark"),
                ("Accept-Language", "pt-BR"),
            ],
            identity: "alice@example.com",
            output: "first"
        )

        let record = try await storedRecord(testState)

        #expect(Set(record.keys) == [Self.identityField, "accept-language"])
        #expect(record[Self.identityField]?.hasPrefix("sha256:") == true)
        #expect(record["accept-language"] == "pt-BR")
    }

    @Test
    func identity_isNeverWrittenToTheDisk() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        let identity = "alice-identity@example.com"

        _ = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer alice-token")],
            identity: identity,
            output: "first"
        )

        let record = try await storedRecord(testState)
        #expect(record.values.allSatisfy { !$0.contains(identity) })

        // Every file of the cache directory: the record as it is on the disk.
        let directoryURL = testState.dataCache.directoryURL
        let enumerator = try #require(FileManager.default.enumerator(atPath: directoryURL.path))
        var scanned = 0
        var foundRecord = false

        while let relative = enumerator.nextObject() as? String {
            // A directory cannot be read as data, and is skipped.
            guard let bytes = try? Data(contentsOf: directoryURL.appendingPathComponent(relative)) else {
                continue
            }

            scanned += 1
            foundRecord = foundRecord || bytes.range(of: Data(Self.identityField.utf8)) != nil

            #expect(bytes.range(of: Data(identity.utf8)) == nil, "\(relative)")
            #expect(bytes.range(of: Data("alice-token".utf8)) == nil, "\(relative)")
        }

        // The scan reached the record, which is where the digest is.
        #expect(scanned > 0)
        #expect(foundRecord)
    }

    // MARK: - Records written without an identity

    /// What a record looked like before the identity existed: it has the credentials and no
    /// identity key, and keeps matching as it did.
    @Test
    func identity_whenTheRecordHasNone_matchesTheCredentialsAsBefore() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        _ = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer alice-token")],
            output: "first"
        )

        let record = try await storedRecord(testState)
        #expect(record[Self.identityField] == nil)
        #expect(Set(record.keys) == ["authorization", "cookie", "proxy-authorization"])

        let sameCredential = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer alice-token")],
            output: "second"
        )

        #expect(sameCredential == "first")

        let otherCredential = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer bob-token")],
            output: "third"
        )

        #expect(otherCredential != "first")
    }

    /// Built by hand, the way the version before this one wrote it, so it is the record and not
    /// what the current code stores that is under test.
    @Test
    func identity_whenAHandWrittenOldRecordHasNone_matchesTheCredentialsAsBefore() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        let cacheKey = "https://localhost:8888" + testState.uri
        let body = try HTTPResult(receivedBytes: 0, response: "cached").encode()
        let stored = await mockCachedData(makeHeaders(maxAgeSeconds: 3_600), body: body)

        await testState.dataCache.setCachedData(
            CachedData(
                cachedResponse: CachedResponse(
                    response: stored.cachedResponse.response,
                    policy: .all,
                    varyRequestHeaders: [
                        "authorization": Internals.CacheControl.digest(
                            ofCredential: "Bearer alice-token",
                            field: "authorization"
                        ),
                        "cookie": "",
                        "proxy-authorization": "",
                    ]
                ),
                buffer: stored.buffer
            ),
            forKey: cacheKey
        )

        let sameCredential = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer alice-token")],
            output: "network"
        )

        #expect(sameCredential == "cached")

        // And it is still not given to a request that declares an identity.
        let withIdentity = try await identityRequest(
            testState,
            requestHeaders: [("Authorization", "Bearer alice-token")],
            identity: "alice",
            output: "network"
        )

        #expect(withIdentity == "network")
    }
}
