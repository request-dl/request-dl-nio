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

    /// Completes a real mTLS handshake under `.urlSession` through the *public* `DataTask` entry
    /// point specifically -- the same way `dataTask_whenCAEnabled` (`DataTaskTests`, pinned to
    /// `.nio`) and `DataTaskTests.dataTask_whenCAEnabledUnderNIOTransportServices` (pinned to
    /// `.nioTransportServices`) already do for the other two executors, completing the trio.
    ///
    /// `RequestConfigurationURLSessionClientMTLSTests
    /// .urlSessionClient_whenMTLSConfigured_completesHandshakeMatchingNIOBackend` already covers
    /// `.urlSession` mTLS success too, but drives `Internals.URLSessionClient` directly; nothing
    /// else exercised this same success through `DataTask` itself.
    ///
    /// Needs `LocalServer.TLSOption.client` (server-side client-certificate verification), only
    /// implemented on the NIOSSL backend.
    ///
    /// The Keychain round trip this needs genuinely succeeds on real macOS (bare `swift test` or
    /// an Xcode-run macOS test bundle) once `Internals.RawBytesIdentityBuilder.makeIdentity(_:_:)`
    /// sets `kSecAttrApplicationLabel` correctly -- confirmed, not assumed, and no longer a known
    /// issue there. Every other Apple platform's Simulator, reached only via `xcodebuild test`
    /// against SwiftPM's auto-generated scheme, has no `.entitlements` file to add Keychain
    /// Sharing to at all, so `SecItemAdd` there fails with `errSecMissingEntitlement` before
    /// identity pairing is ever reached, surfacing through the public `DataTask` API as
    /// `ClientIdentityError` -- a genuinely different, still-open gap, confirmed directly on
    /// iOS/tvOS/watchOS Simulator CI runs.
    @Test
    func dataTask_whenCAEnabledUnderURLSession() async throws {
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

        // When / Then
        func verify() async throws {
            let data = try await DataTask { content }.extractPayload().result()
            let result = try HTTPResult<String>(data)
            #expect(result.response == output)
        }

        #if os(macOS) || !canImport(Darwin)
        try await verify()
        #else
        await withKnownIssue(
            "no Keychain Sharing entitlement on this platform's SwiftPM-generated Xcode scheme; see this test's own doc comment"
        ) {
            try await verify()
        }
        #endif
    }
}

#endif
