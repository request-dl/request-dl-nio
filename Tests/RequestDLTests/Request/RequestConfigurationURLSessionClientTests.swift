//
// See LICENSE for this package's licensing information.
//

import NIOSSL
import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Security

/// Phase 5a of `URLSESSION_TASK.md`: a non-streaming request/response round trip through
/// `Internals.URLSessionClient`, forced onto `.urlSession` via `requireExecutor(_:)` (Phase 3)
/// rather than through the public `DataTask` API -- `Session.requiredExecutor(_:)` is Phase 7,
/// not built yet, so there is no way to pin an executor from a `Property` tree today.
///
/// Mirrors `DataTaskTests.dataTask()` (same `LocalServer`/`ResponseConfiguration` fixtures, same
/// `{"receivedBytes", "response"}` envelope), but drives `RequestConfiguration.buildURLRequest()`
/// + `Internals.URLSessionClient` directly instead of `DataTask`, and skips `SecureConnection`
/// entirely -- no TLS customization is in scope for 5a, so trusting `LocalServer`'s self-signed
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

/// Phase 5e of `URLSESSION_TASK.md`: the TLS/mTLS challenge handling promoted from
/// `Internals.RawBytesIdentityBuilder`/`Internals.URLSessionIdentityPolicy` -- built from
/// whatever `Internals.SecureConnection` the resolved `Property` tree carries, same as the NIO
/// backend, instead of the `AcceptAnyServerTrustDelegate` workaround the still-TLS-unaware Phase
/// 5a test above needs.
///
/// **The client-identity round trip (`urlSessionClient_whenMTLSConfigured_...` below) is a known
/// issue running through this bare SwiftPM test harness on *any* platform, not macOS
/// specifically** -- confirmed by actually running it both ways, not assumed: on macOS (`swift
/// test`, unsigned CLI binary) and on an iOS Simulator (`xcodebuild test -scheme request-dl`,
/// SwiftPM's auto-generated scheme), both fail identically with
/// `Internals.RawBytesIdentityBuilder.Error.missingKeychainSharingEntitlement`'s exact message --
/// which is itself the confirmation the actionable-error-wrapping half of Phase 5e works
/// correctly on both. The common thread is not the OS, it's that neither run carries a Keychain
/// Sharing entitlement: `swift test` produces a bare unsigned binary, and SwiftPM's
/// auto-generated Xcode scheme has no `.entitlements` file to add the capability to (there is
/// nowhere in a `Package.swift`-only project to configure it -- see
/// HOW_TO_USE_CERTIFICATE_URLSESSION.md, which is written for a real app target's Signing &
/// Capabilities tab, not a SwiftPM test bundle). A properly configured Xcode *app* project/target
/// (or extension) with Keychain Sharing added -- the setup HOW_TO_USE_CERTIFICATE_URLSESSION.md
/// walks through, and what the original spike this promotes from was validated against -- is
/// expected to complete this same round trip for real; this suite cannot exercise that shape of
/// project. The server-trust-only tests below it (no client identity involved) are unaffected by
/// any of this and genuinely pass on macOS, iOS Simulator, and Linux (Docker, `swift:6.2`) alike
/// -- Linux and Simulator confirmed directly, not assumed either. `Internals.URLSessionClient`
/// and everything under `Sources/RequestDLInternals/.../URLSession Client/` is Apple-only
/// (`canImport(Darwin)`-gated) by design, so this whole test file compiles to nothing on Linux;
/// only `CertificateFixturesExpirationTests` (fixture-only, no TLS handshake) runs there, and
/// does.
struct RequestConfigurationURLSessionClientMTLSTests {

    /// Direct port of `DataTaskTests.dataTask_whenCAEnabled` -- same `LocalServer`/`Certificates`
    /// fixtures, same `Certificate`/`PrivateKey`/`TrustRoots` sources (file paths, PEM, RSA), but
    /// forced onto `.urlSession` instead of driven through `DataTask`. See the type doc comment
    /// for why this specific test is a known issue in this test harness, on every platform.
    @Test
    func urlSessionClient_whenMTLSConfigured_completesHandshakeMatchingNIOBackend() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let uri = "/" + UUID().uuidString

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                // Dedicated port -- 8887/8888/8889 are already claimed by other
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

        // When
        try resolved.session.configuration.requireExecutor(.urlSession)

        let request = try await resolved.requestConfiguration.buildURLRequest()

        // Then -- see the type doc comment: known issue in this bare SwiftPM test harness on
        // every platform (confirmed on macOS and iOS Simulator directly), not a defect in the
        // mapping this test otherwise exercises, and not specific to macOS.
        await withKnownIssue(
            "this SwiftPM test harness has no Keychain Sharing entitlement on any platform -- see the type doc comment",
            {
                let urlSessionClient = try Internals.URLSessionClient(
                    configuration: .ephemeral,
                    secureConnection: resolved.session.configuration.secureConnection
                )
                let result = try await urlSessionClient.execute(request: request)

                let decoded = try HTTPResult<String>(result.body)
                #expect(decoded.response == output)
            }
        )
    }

    /// `trustRoots` alone (no client identity) -- confirms the server-trust half of
    /// `Internals.URLSessionIdentityPolicy` works independently of the client-certificate half.
    ///
    /// Needs `.scripts/generate-test-certificates.sh`'s fixtures (SAN, `extendedKeyUsage`, a
    /// validity period under Apple's enforced cap) to pass at all -- the original 30-year,
    /// EKU-less fixtures failed `SecTrustEvaluateWithError` outright even when explicitly
    /// anchored via `SecTrustSetAnchorCertificates`, a `SecPolicyCreateSSL` enforcement uniform
    /// across every Apple platform that NIOSSL's own validation (what
    /// `DataTaskTests.dataTask_whenCAEnabled` exercises for the same fixture) has no equivalent
    /// of. See `URLSESSION_TASK.md`, Phase 5e. `CertificateFixturesExpirationTests` guards
    /// against these fixtures going stale again.
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
    /// configured at all -- and, unlike the two tests above, does so against a server whose
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
    /// request fails -- the same shape of failure `.fullVerification`/no-`TrustRoots` would hit,
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

/// Test-only stand-in for the TLS challenge handling Phase 5e adds for real -- `LocalServer` is
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
