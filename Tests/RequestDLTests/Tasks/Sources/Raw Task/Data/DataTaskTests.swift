//
// See LICENSE for this package's licensing information.
//

import NIOSSL
import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
import struct Foundation.Data
#endif

struct DataTaskTests {

    @Test
    func dataTask() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)
    }

    /// A deadline this short is guaranteed to already have elapsed by the time the request even
    /// reaches the network: deterministic without needing an artificially slow server, the same
    /// technique real-network cancellation tests elsewhere in this suite rely on.
    @Test
    func dataTask_whenResourceTimeoutAlreadyElapsed_throwsResourceTimeoutError() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        let certificate = Certificates().server()

        let response = try LocalServer.ResponseConfiguration(jsonObject: "Hello World")
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When / Then
        await #expect(throws: ResourceTimeoutError.self) {
            try await DataTask {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer
                Timeout(.nanoseconds(1), for: .resource)

                SecureConnection {
                    TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
                }
            }
            .extractPayload()
            .result()
        }
    }

    @Test
    func dataTask_whenResourceTimeoutNotExceeded_completesNormally() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer
            Timeout(.seconds(30), for: .resource)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)
    }

    /// Pinned to `.nio`: a real client-certificate handshake over `.urlSession` is a confirmed,
    /// unconditional `withKnownIssue` on this SwiftPM test harness (no Keychain Sharing
    /// entitlement on any platform; see `RequestConfigurationURLSessionClientMTLSTests`'s type
    /// doc comment, which already tracks this exact gap at the `Internals.URLSessionClient`
    /// layer).
    ///
    /// Since `resolveExecutor()` decides which backend a real `DataTask` runs over, this test
    /// would otherwise hit that same unconditional gap by default and fail for a reason that has
    /// nothing to do with what it's actually verifying: that mTLS client-cert auth works end to
    /// end through the public `DataTask` API, which NIO already does reliably.
    @Test
    func dataTask_whenCAEnabled() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let uri = "/" + UUID().uuidString

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8887,
                option: .client(client)
            )
        )

        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer
                .requiredExecutor(.nio)

            SecureConnection {
                TrustRoots(server.certificateURL.absolutePath(percentEncoded: false))
                RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
                PrivateKey(client.privateKeyURL.absolutePath(percentEncoded: false))
            }
            .verification(.fullVerification)
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)
    }

    /// Regression coverage for the crash `Internals.SecureConnection.build(isCompatibleWithNetworkFramework:)`
    /// fixed: `certificateChain`/`privateKey` used to always land on the same `TLSConfiguration`
    /// AsyncHTTPClient's NIOTransportServices bridge also reads, which `preconditionFailure`s the
    /// instant either is non-empty, regardless of the Network.framework-native identity also
    /// being supplied correctly via `tlsLocalIdentityNetworkFramework`.
    ///
    /// Reachable in practice via `enableNetworkFramework(true)`/
    /// `preferredExecutor(.nioTransportServices)`/this test's own
    /// `requiredExecutor(.nioTransportServices)` any time mTLS is also configured; nothing in
    /// `networkFrameworkIncompatibilityReasons()` ever stood in the way, since mTLS is genuinely
    /// supported there, just through a different channel.
    ///
    /// Wrapped in the same unconditional `withKnownIssue` as `dataTask_whenCAEnabled` above (no
    /// Keychain Sharing entitlement on this SwiftPM test harness): what this specifically proves,
    /// independent of whether the Keychain round-trip itself succeeds here, is that reaching this
    /// codepath no longer crashes the process.
    @Test
    func dataTask_whenCAEnabledUnderNIOTransportServices() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let uri = "/" + UUID().uuidString

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8896,
                option: .client(client)
            )
        )

        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When / Then
        func verify() async throws {
            let data = try await DataTask {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer
                    .requiredExecutor(.nioTransportServices)

                SecureConnection {
                    TrustRoots(server.certificateURL.absolutePath(percentEncoded: false))
                    RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
                    PrivateKey(client.privateKeyURL.absolutePath(percentEncoded: false))
                }
                .verification(.fullVerification)
            }
            .extractPayload()
            .result()

            let result = try HTTPResult<String>(data)
            #expect(result.response == output)
        }

        // The Keychain round-trip this "known issue" is about only happens inside
        // `#if canImport(Darwin)` code (the mTLS identity Network.framework needs); off Darwin,
        // `.nioTransportServices` never touches the Keychain at all, so `verify()` succeeds
        // outright there and `withKnownIssue` would fail the test for not hitting an issue that
        // was never reachable off Darwin to begin with.
        #if canImport(Darwin)
        await withKnownIssue(
            "this SwiftPM test harness has no Keychain Sharing entitlement on any platform; see RequestConfigurationURLSessionClientMTLSTests's type doc comment"
        ) {
            try await verify()
        }
        #else
        try await verify()
        #endif
    }

    /// Regression coverage for the gap `Internals.NIOTrustEvaluator` closed: `additionalTrustRoots`
    /// alone, with no SPKI pinning, used to be silently ignored under Network.framework.
    /// `localServer`'s certificate is signed by a private test CA the system default trust store
    /// has never heard of (see `dataTask_whenCAEnabled` above), so this handshake only succeeds if
    /// `AdditionalTrustRoots` genuinely reached Network.framework's own trust evaluation, not just
    /// NIOSSL's `.nio` backend.
    @Test
    func dataTask_whenAdditionalTrustRootsSetAndNIOTransportServicesRequired_completesHandshakeWithoutSPKIPinning()
        async throws
    {
        // Given
        let server = Certificates().server()
        let uri = "/" + UUID().uuidString

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8893,
                option: .none
            )
        )

        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer
                .requiredExecutor(.nioTransportServices)

            SecureConnection {
                AdditionalTrustRoots(server.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)
    }

    /// Regression coverage for the gap `Internals.NIOTrustEvaluator` closed: `.noHostnameVerification`
    /// alone used to trap under Network.framework (AsyncHTTPClient's own `precondition`, unless a
    /// custom verification callback is installed).
    ///
    /// Paired with `dataTask_whenNoHostnameVerificationSetWithoutTrustRoots_stillRejectsUntrustedCertificate`
    /// below (chain trust still enforced with no `TrustRoots`), this proves the fix skips exactly
    /// the hostname check and nothing more. `Internals.NIOTrustEvaluator` swaps the `SecTrust`'s
    /// policy for a hostname-less one but still anchors it on `TrustRoots`/`additionalTrustRoots`
    /// and still evaluates the chain.
    @Test
    func dataTask_whenNoHostnameVerificationSetWithTrustRoots_completesHandshakeUnderNIOTransportServices()
        async throws
    {
        // Given
        let server = Certificates().server()
        let uri = "/" + UUID().uuidString

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8894,
                option: .none
            )
        )

        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer
                .requiredExecutor(.nioTransportServices)

            SecureConnection {
                TrustRoots(server.certificateURL.absolutePath(percentEncoded: false))
            }
            .verification(.noHostnameVerification)
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)
    }

    /// The other half of the pair above: with no `TrustRoots` to vouch for this self-signed test
    /// certificate, the handshake must still fail even though `.noHostnameVerification` turns off
    /// hostname matching, proving that flag alone never became "trust everything."
    @Test
    func dataTask_whenNoHostnameVerificationSetWithoutTrustRoots_stillRejectsUntrustedCertificate() async throws {
        // Given
        let uri = "/" + UUID().uuidString

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8895,
                option: .none
            )
        )

        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When / Then
        await #expect(throws: (any Error).self) {
            try await DataTask {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer
                    .requiredExecutor(.nioTransportServices)

                SecureConnection {}
                    .verification(.noHostnameVerification)
            }
            .extractPayload()
            .result()
        }
    }
}

extension DataTaskTests {

    private final class PSKClientIdentityResolver: SSLPSKIdentityResolver {

        let key: String
        let identity: String

        init(key: String, identity: String) {
            self.key = key
            self.identity = identity
        }

        func callAsFunction(_ context: PSKClientContext) throws -> PSKClientIdentityResponse {
            var bytes = NIOSSLSecureBytes()
            bytes.append(key.utf8)
            bytes.append(":\(identity)".utf8)
            bytes.append(":\(identity)".utf8)
            bytes.append(":pskHint".utf8)
            return .init(key: bytes, identity: identity)
        }
    }

    @Test
    func dataTask_whenPSK() async throws {
        // Given
        let uri = "/" + UUID().uuidString
        let output = "Hello World"

        let identity = "client"
        let key = """
            ff135dfc9c802f584fd8b7bb3284fae0e1c404e4f8ac9217ff1b1bdecb\
            d4cfa5651253143700a94c89227f5db03ed2de86a2914b4da0259901a4\
            bbaf8a1dee0f
            """

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8886,
                option: .psk(Data(key.utf8), identity)
            )
        )

        let response = try LocalServer.ResponseConfiguration(
            jsonObject: output
        )

        localServer.insert(response, at: uri)

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer

            SecureConnection {
                PSKIdentity(
                    PSKClientIdentityResolver(
                        key: key,
                        identity: identity
                    )
                )
                .hint("pskHint")
            }
            .verification(.none)
            .version(minimum: .v1, maximum: .v1_2)
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)
    }

    /// `Session.requiredExecutor(_:)` must fail loudly at request time, not silently run on a
    /// different executor: this is `RawTask`'s own validation throwing `ExecutorRequirementError`,
    /// exercised through the real public `DataTask` entry point rather than by calling
    /// `Internals.Session.Configuration.requireExecutor(_:)` directly (already covered in
    /// `InternalsSessionConfigurationExecutorTests`).
    ///
    /// No `LocalServer` needed: the throw happens before any client is built or network I/O
    /// starts.
    @Test
    func dataTask_whenRequiredExecutorIsIncompatible_throwsActionableErrorBeforeAnyNetworkIO() async throws {
        // Given: a custom cipher suite has no Network.framework equivalent at all (silently
        // dropped rather than trapped, but still flagged incompatible so it isn't lost without a
        // signal), so pinning `.nioTransportServices` is guaranteed to conflict.
        let task = DataTask {
            BaseURL("localhost")

            Session()
                .requiredExecutor(.nioTransportServices)

            SecureConnection {}
                .cipherSuites(.TLS_AES_128_GCM_SHA256)
        }
        .extractPayload()

        // When / Then
        await #expect(throws: ExecutorRequirementError.self) {
            try await task.result()
        }

        do {
            _ = try await task.result()
            Issue.record("Not expecting success")
        } catch let error as ExecutorRequirementError {
            // Then: actionable, not just "it throws". Names the pinned executor, the
            // conflicting field, and points at the escape hatch.
            #expect(error.requiredExecutor == .nioTransportServices)
            #expect(error.reasons == [.cipherSuiteValues])
            #expect(error.description.contains(".requiredExecutor(.nioTransportServices)"))
            #expect(error.description.contains(".preferredExecutor(_:)"))
        }
    }

    /// Counterpart to the test above: a `requiredExecutor` the configuration *can* actually run
    /// on must not throw, proving the validation doesn't reject compatible configurations along
    /// the way.
    @Test
    func dataTask_whenRequiredExecutorIsCompatible_doesNotThrowExecutorRequirementError() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer
                .requiredExecutor(.nio)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)
    }
}
