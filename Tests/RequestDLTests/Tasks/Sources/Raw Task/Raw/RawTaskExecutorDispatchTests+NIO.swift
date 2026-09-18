//
// See LICENSE for this package's licensing information.
//

// The `.nio`-pinned (and Keychain-gap) half of `RawTaskExecutorDispatchTests` (see the main
// declaration's own doc comment, in `RawTaskExecutorDispatchTests.swift`), split out because
// these tests either pin `.requiredExecutor(.nio)` and check for `.nio` case of
// `resolvedClient()` (only exists with NIOCore) or need `LocalServer.TLSOption.client`
// (server-side client-certificate verification, not implemented on the portable `NWListener`
// backend -- see `LocalServer.TLSOption.makeLocalIdentity()`'s own doc comment).
#if canImport(Darwin) && canImport(NIOCore)

import Testing

@testable import RequestDL
@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
import class Foundation.ProcessInfo
#endif

extension RawTaskExecutorDispatchTests {

    /// Regression coverage for the bug this phase's own testing caught: `requiredExecutor(.nio)`
    /// used to validate without ever actually being the executor a real request dispatched
    /// over, since `resolveExecutor()` read only `preferredExecutor`, so a
    /// `.urlSession`-compatible config kept resolving there anyway.
    ///
    /// See `InternalsSessionConfigurationExecutorTests`'s "resolveExecutor() with
    /// requiredExecutor" section for the unit-level fix; this is the same fact proven one
    /// layer up, through a real `DataTask` round trip.
    @Test
    func dataTask_whenNIORequired_actuallyDispatchesOverNIOEvenThoughURLSessionWouldBeCompatible() async throws {
        // Given: same shape as `dataTask_whenNoExecutorPreferenceSet_...` (would default to
        // `.urlSession` on Darwin), but this time pinned to `.nio` explicitly.
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let content = TestProperty {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session("com.requestdl.tests.7b3-dispatch.\(UUID())")
                .requiredExecutor(.nio)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }

        // When
        let data = try await DataTask { content }.extractPayload().result()

        let result = try HTTPResult<String>(data)
        #expect(result.response == output)

        // Then
        let resolved = try await resolve(content)

        guard case .nio = try await resolved.session.resolvedClient() else {
            Issue.record("Expected the DataTask call above to have dispatched over .nio")
            return
        }
    }

    /// Companion to `dataTask_withDefaultUserAgentOverURLSession_defersToURLSessionsNativeReport`/
    /// `dataTask_withCustomUserAgentOverURLSession_reachesTheWireUntouched`: NIO never
    /// synthesizes its own `User-Agent`, so dropping RequestDL's default there, the way
    /// `.urlSession` does, would just send the request with none. RequestDL's neutral default
    /// must survive under `.nio`.
    @Test
    func dataTask_withDefaultUserAgentOverNIO_keepsRequestDLsNeutralDefault() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let certificate = Certificates().server()

        let response = try LocalServer.ResponseConfiguration(jsonObject: "Hello World")
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let content = TestProperty {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session("com.requestdl.tests.useragent-nio.\(UUID())")
                .requiredExecutor(.nio)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }

            UserAgentHeader()
        }

        // When
        let data = try await DataTask { content }.extractPayload().result()
        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.receivedUserAgentHeader == ProcessInfo.processInfo.userAgent)
    }

    /// Confirms the identity-building failure a real mTLS `DataTask` hits under `.urlSession` on
    /// this SwiftPM test harness (no Keychain Sharing entitlement; see
    /// `RequestConfigurationURLSessionClientMTLSTests`'s own doc comment) surfaces through the
    /// *public* API as a documented ``ClientIdentityError``, not a raw
    /// `Internals.RawBytesIdentityBuilder.Error`/`Internals.URLSessionIdentityPolicy
    /// .ConfigurationError`. Both are package-visible types a real consumer app cannot even name,
    /// and whose `localizedDescription` (Foundation's generic NSError fallback, absent this fix)
    /// carries none of their own actionable `description` text.
    ///
    /// `ClientIdentityErrorTests` covers the rewrap/description logic itself in isolation; this
    /// is the same fact proven end to end, through the real `DataTask` entry point, the same way
    /// `dataTask_whenCAEnabled` (`DataTaskTests`, pinned to `.nio` specifically to avoid this
    /// exact gap) already does for the NIO backend.
    ///
    /// Deliberately does not assert on the *specific* ``ClientIdentityError/Reason``: this
    /// harness has been observed to hit this gap two different ways (`errSecMissingEntitlement`
    /// on `SecItemAdd`, or `errSecItemNotFound` on the identity lookup right after a successful
    /// add), and both are genuine, independently-reachable failure modes this test should pass
    /// under either way.
    ///
    /// Needs `LocalServer.TLSOption.client` (server-side client-certificate verification), only
    /// implemented on the NIOSSL backend.
    @Test
    func dataTask_whenCAEnabledUnderURLSessionWithoutKeychainSharing_throwsClientIdentityError() async throws {
        let server = Certificates().server()
        let client = Certificates().client()

        let uri = "/" + UUID().uuidString

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8885,
                option: .client(client)
            )
        )

        let output = "Hello World"
        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let content = TestProperty {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session("com.requestdl.tests.phase8-identity.\(UUID())")
                .requiredExecutor(.urlSession)

            SecureConnection {
                TrustRoots(server.certificateURL.absolutePath(percentEncoded: false))
                RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
                PrivateKey(client.privateKeyURL.absolutePath(percentEncoded: false))
            }
            .verification(.fullVerification)
        }

        do {
            _ = try await DataTask { content }.extractPayload().result()
            Issue.record("Expected this SwiftPM test harness's missing Keychain Sharing entitlement to throw")
        } catch let error as ClientIdentityError {
            // Then: the public, documented type, not a leaked internal one, with the same
            // actionable text through both access paths a real caller might use.
            #expect(!error.description.isEmpty)
            #expect((error as any Error).localizedDescription == error.description)
        } catch {
            Issue.record("Expected ClientIdentityError, got \(type(of: error)): \(error)")
        }
    }
}

#endif
