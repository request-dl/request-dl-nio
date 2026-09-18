//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Security

/// A non-streaming request/response round trip through `Internals.URLSessionClient`, forced onto
/// `.urlSession` via `requireExecutor(_:)` directly at the `Internals` layer rather than through
/// the public `DataTask` API (`RawTaskExecutorDispatchTests` covers that end-to-end path).
///
/// Mirrors `DataTaskTests.dataTask()` (same `LocalServer`/`ResponseConfiguration` fixtures, same
/// `{"receivedBytes", "response"}` envelope), but drives `RequestConfiguration.buildURLRequest()`
/// + `Internals.URLSessionClient` directly instead of `DataTask`, and skips `SecureConnection`
/// entirely: no TLS customization is in scope here, so trusting `LocalServer`'s self-signed
/// certificate is handled by a test-only `URLSessionTaskDelegate` instead.
struct RequestConfigurationURLSessionClientTests {

    @Test
    func urlSessionClient_whenExecutingResolvedRequest_matchesDataTaskRoundTrip() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let resolved = try await resolve(
            TestProperty {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer
            }
        )

        // When
        try resolved.session.configuration.requireExecutor(.urlSession)

        let request = try await resolved.requestConfiguration.buildURLRequest()

        let client = try Internals.URLSessionClient(configuration: .ephemeral)
        let result = try await client.execute(
            request: request,
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then
        #expect(result.head.status.code == 200)

        let decoded = try HTTPResult<String>(result.body)
        #expect(decoded.receivedBytes == .zero)
        #expect(decoded.response == output)
    }
}

/// The TLS/mTLS challenge handling promoted from `Internals.RawBytesIdentityBuilder`/
/// `Internals.URLSessionIdentityPolicy`: built from whatever `Internals.SecureConnection` the
/// resolved `Property` tree carries, same as the NIO backend, instead of the
/// `AcceptAnyServerTrustDelegate` workaround the still-TLS-unaware test above needs.
///
/// `Internals.URLSessionClient`
/// and everything under `Sources/RequestDLInternals/.../URLSession Client/` is Apple-only
/// (`canImport(Darwin)`-gated) by design, so this whole test file compiles to nothing on Linux;
/// only `CertificateFixturesExpirationTests` (fixture-only, no TLS handshake) runs there, and
/// does.
struct RequestConfigurationURLSessionClientMTLSTests {

    /// Direct port of `DataTaskTests.dataTask_whenCAEnabled`: same `LocalServer`/`Certificates`
    /// fixtures, same `Certificate`/`PrivateKey`/`TrustRoots` sources (file paths, PEM, RSA), but
    /// forced onto `.urlSession` instead of driven through `DataTask`.
    ///
    /// The Keychain round trip this needs genuinely succeeds on real macOS (bare `swift test` or
    /// an Xcode-run macOS test bundle) once `Internals.RawBytesIdentityBuilder.makeIdentity(_:_:)`
    /// sets `kSecAttrApplicationLabel` correctly -- confirmed, not assumed, and no longer a known
    /// issue there. Every other Apple platform's Simulator, reached only via `xcodebuild test`
    /// against SwiftPM's auto-generated scheme, has no `.entitlements` file to add Keychain
    /// Sharing to at all, so `SecItemAdd` there fails with `errSecMissingEntitlement` before
    /// identity pairing is ever reached -- a genuinely different, still-open gap, confirmed
    /// directly on iOS/tvOS/watchOS Simulator CI runs.
    @Test
    func urlSessionClient_whenMTLSConfigured_completesHandshakeMatchingNIOBackend() async throws {
        // `LocalServer.TLSOption.client(_:)` (server-side mTLS verification, needed to even
        // construct the `LocalServer` this test drives against) has no Network.framework
        // equivalent under a NIOCore-free build -- see that type's own doc comment. Under
        // NIOCore this whole body runs for real; without it, everything from construction
        // onward is expected to throw, so it is wrapped wholesale rather than gated
        // piecemeal.
        func run() async throws {
            // Given
            let server = Certificates().server()
            let client = Certificates().client()

            let uri = "/" + UUID().uuidString

            let localServer = try await LocalServer(
                LocalServer.Configuration(
                    host: "localhost",
                    // Dedicated port: 8887/8888/8889 are already claimed by other
                    // LocalServer-backed suites (see LocalServer.Configuration.swift / DataTaskTests.swift).
                    port: 8892,
                    option: .client(client)
                )
            )

            let output = "Hello World"
            let response = try LocalServer.ResponseConfiguration(jsonObject: output)

            localServer.cleanup(at: uri)
            localServer.insert(response, at: uri)
            defer { localServer.cleanup(at: uri) }

            let resolved = try await resolve(
                TestProperty {
                    BaseURL(localServer.baseURL)
                    Path(uri)

                    Session.localServer

                    SecureConnection {
                        TrustRoots(server.certificateURL.absolutePath(percentEncoded: false))
                        RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
                        PrivateKey(client.privateKeyURL.absolutePath(percentEncoded: false))
                    }
                    .verification(.fullVerification)
                }
            )

            // When / Then
            try resolved.session.configuration.requireExecutor(.urlSession)

            let request = try await resolved.requestConfiguration.buildURLRequest()

            func verify() async throws {
                let urlSessionClient = try Internals.URLSessionClient(
                    configuration: .ephemeral,
                    secureConnection: resolved.session.configuration.secureConnection
                )
                let result = try await urlSessionClient.execute(request: request)

                let decoded = try HTTPResult<String>(result.body)
                #expect(decoded.response == output)
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

        #if canImport(NIOCore)
        try await run()
        #else
        await withKnownIssue(
            """
            LocalServer.TLSOption.client(_:) (server-side mTLS verification) has no \
            Network.framework equivalent under a NIOCore-free build
            """
        ) {
            try await run()
        }
        #endif
    }

    /// `trustRoots` alone (no client identity): confirms the server-trust half of
    /// `Internals.URLSessionIdentityPolicy` works independently of the client-certificate half.
    ///
    /// Needs `.scripts/generate-test-certificates.sh`'s fixtures (SAN, `extendedKeyUsage`, a
    /// validity period under Apple's enforced cap) to pass at all. The original 30-year,
    /// EKU-less fixtures failed `SecTrustEvaluateWithError` outright even when explicitly
    /// anchored via `SecTrustSetAnchorCertificates`, a `SecPolicyCreateSSL` enforcement uniform
    /// across every Apple platform that NIOSSL's own validation (what
    /// `DataTaskTests.dataTask_whenCAEnabled` exercises for the same fixture) has no equivalent
    /// of. `CertificateFixturesExpirationTests` guards against these fixtures going stale again.
    @Test
    func urlSessionClient_whenTrustRootsConfigured_verifiesServerCertificateAgainstThem() async throws {
        // Given
        let server = Certificates().server()
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let resolved = try await resolve(
            TestProperty {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer

                SecureConnection {
                    TrustRoots(server.certificateURL.absolutePath(percentEncoded: false))
                }
                .verification(.fullVerification)
            }
        )

        // When
        try resolved.session.configuration.requireExecutor(.urlSession)

        let request = try await resolved.requestConfiguration.buildURLRequest()

        let urlSessionClient = try Internals.URLSessionClient(
            configuration: .ephemeral,
            secureConnection: resolved.session.configuration.secureConnection
        )
        let result = try await urlSessionClient.execute(request: request)

        // Then
        let decoded = try HTTPResult<String>(result.body)
        #expect(decoded.response == output)
    }

    /// `.none` verification accepts `LocalServer`'s self-signed certificate with no `TrustRoots`
    /// configured at all. Unlike the two tests above, it does so against a server whose
    /// certificate is not otherwise trusted, which is what makes this meaningfully different from
    /// `.fullVerification` rather than a tautology (see the paired rejection test below).
    @Test
    func urlSessionClient_whenVerificationIsNone_acceptsUntrustedServerCertificate() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let resolved = try await resolve(
            TestProperty {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer

                SecureConnection {}
                    .verification(.none)
            }
        )

        // When
        try resolved.session.configuration.requireExecutor(.urlSession)

        let request = try await resolved.requestConfiguration.buildURLRequest()

        let urlSessionClient = try Internals.URLSessionClient(
            configuration: .ephemeral,
            secureConnection: resolved.session.configuration.secureConnection
        )
        let result = try await urlSessionClient.execute(request: request)

        // Then
        let decoded = try HTTPResult<String>(result.body)
        #expect(decoded.response == output)
    }

    /// Proves the two tests above are not tautological: with no `SecureConnection` at all (no
    /// `identityPolicy`, so the TLS challenge falls through to `URLSession`'s own default
    /// handling), `LocalServer`'s self-signed certificate is *not* trusted by the system and the
    /// request fails: the same shape of failure `.fullVerification`/no-`TrustRoots` would hit,
    /// which is exactly why the tests above configure `TrustRoots`/`.none` explicitly.
    @Test
    func urlSessionClient_whenNoSecureConnectionConfigured_rejectsUntrustedServerCertificate() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let resolved = try await resolve(
            TestProperty {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer
            }
        )

        // When
        try resolved.session.configuration.requireExecutor(.urlSession)

        let request = try await resolved.requestConfiguration.buildURLRequest()

        let urlSessionClient = try Internals.URLSessionClient(configuration: .ephemeral)

        // Then
        await #expect(throws: (any Error).self) {
            try await urlSessionClient.execute(request: request)
        }
    }
}

/// Test-only stand-in for the real client's own TLS challenge handling. `LocalServer` is
/// always TLS-terminated with a throwaway self-signed certificate, even outside any TLS feature
/// under test, so *something* has to trust it for a plain, no-customization round trip to
/// complete at all.
private final class AcceptAnyServerTrustDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

#endif
