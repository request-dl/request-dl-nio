//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct ModifiersDigestAuthenticationTests {

    private static let challengeHeader =
        #"Digest realm="test", qop="auth", nonce="abc123", opaque="xyz", algorithm=MD5"#

    private func head(status: UInt, wwwAuthenticate: String? = nil) -> ResponseHead {
        ResponseHead(
            url: nil,
            status: .init(code: status, reason: ""),
            version: .init(minor: 1, major: 1),
            headers: wwwAuthenticate.map { ["WWW-Authenticate": $0] } ?? [:],
            isKeepAlive: true
        )
    }

    @Test
    func digestAuthentication_whenChallengedThenAuthenticated_retriesAndSucceeds() async throws {
        // Given
        let credential = DigestCredential()
        let attempts = InlineProperty(wrappedValue: 0)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
            DigestAuthentication(username: "user", password: "pass")
        }
        .collectData()
        .flatMap { result -> TaskResult<Data> in
            attempts.wrappedValue += 1

            guard attempts.wrappedValue > 1 else {
                return TaskResult(head: head(status: 401, wwwAuthenticate: Self.challengeHeader), payload: Data())
            }

            return TaskResult(head: head(status: 200), payload: Data("ok".utf8))
        }
        .digestAuthentication(credential)
        .result()

        // Then
        #expect(attempts.wrappedValue == 2)
        #expect(result.payload == Data("ok".utf8))
        #expect(result.head.status.code == 200)
        #expect(credential.challenge != nil)
    }

    @Test
    func digestAuthentication_whenNoCredentialPassed_stillRetriesAndSucceeds() async throws {
        // Given -- no DigestCredential constructed or passed anywhere; `.digestAuthentication()`
        // must create and thread its own through the environment for `DigestAuthentication` to
        // pick up.
        let attempts = InlineProperty(wrappedValue: 0)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
            DigestAuthentication(username: "user", password: "pass")
        }
        .collectData()
        .flatMap { result -> TaskResult<Data> in
            attempts.wrappedValue += 1

            guard attempts.wrappedValue > 1 else {
                return TaskResult(head: head(status: 401, wwwAuthenticate: Self.challengeHeader), payload: Data())
            }

            return TaskResult(head: head(status: 200), payload: Data("ok".utf8))
        }
        .digestAuthentication()
        .result()

        // Then
        #expect(attempts.wrappedValue == 2)
        #expect(result.payload == Data("ok".utf8))
        #expect(result.head.status.code == 200)
    }

    @Test
    func digestAuthentication_whenMaxAttemptsIsOne_doesNotRetry() async throws {
        // Given
        let credential = DigestCredential()
        let attempts = InlineProperty(wrappedValue: 0)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
            DigestAuthentication(username: "user", password: "pass")
        }
        .collectData()
        .flatMap { _ -> TaskResult<Data> in
            attempts.wrappedValue += 1
            return TaskResult(head: head(status: 401, wwwAuthenticate: Self.challengeHeader), payload: Data())
        }
        .digestAuthentication(credential, maxAttempts: 1)
        .result()

        // Then
        #expect(attempts.wrappedValue == 1)
        #expect(result.head.status.code == 401)
        #expect(credential.challenge == nil)
    }

    @Test
    func digestAuthentication_whenChallengeUnparseable_doesNotRetry() async throws {
        // Given
        let credential = DigestCredential()
        let attempts = InlineProperty(wrappedValue: 0)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
        }
        .collectData()
        .flatMap { _ -> TaskResult<Data> in
            attempts.wrappedValue += 1
            return TaskResult(head: head(status: 401, wwwAuthenticate: "Basic realm=\"test\""), payload: Data())
        }
        .digestAuthentication(credential)
        .result()

        // Then
        #expect(attempts.wrappedValue == 1)
        #expect(result.head.status.code == 401)
    }

    @Test
    func digestAuthentication_whenNotUnauthorized_doesNotRetry() async throws {
        // Given
        let credential = DigestCredential()
        let attempts = InlineProperty(wrappedValue: 0)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
        }
        .collectData()
        .flatMap { _ -> TaskResult<Data> in
            attempts.wrappedValue += 1
            return TaskResult(head: head(status: 200), payload: Data("ok".utf8))
        }
        .digestAuthentication(credential)
        .result()

        // Then
        #expect(attempts.wrappedValue == 1)
        #expect(result.payload == Data("ok".utf8))
    }
}
