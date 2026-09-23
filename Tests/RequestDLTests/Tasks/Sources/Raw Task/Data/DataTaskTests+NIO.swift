//
// See LICENSE for this package's licensing information.
//

// The `.nio`/`.nioTransportServices`-pinned half of `DataTaskTests` (see the main declaration's
// own doc comment, in `DataTaskTests.swift`), split out because every test here reaches
// `Session.requiredExecutor(.nio)`/`.requiredExecutor(.nioTransportServices)` or PSK
// (`RequestDL.PSKIdentity`/`NIOSSLSecureBytes`), none of which exist without NIOCore.
#if canImport(NIOCore)

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

extension DataTaskTests {

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
    /// The Keychain round trip this needs genuinely succeeds on real macOS (bare `swift test` or
    /// an Xcode-run macOS test bundle) once `Internals.RawBytesIdentityBuilder.makeIdentity(_:_:)`
    /// sets `kSecAttrApplicationLabel` correctly -- confirmed, not assumed, and no longer a known
    /// issue there. Every other Apple platform's Simulator, reached only via `xcodebuild test`
    /// against SwiftPM's auto-generated scheme, has no `.entitlements` file to add Keychain
    /// Sharing to at all (there is nowhere in a `Package.swift`-only project to configure one;
    /// see `Sources/RequestDL/Documentation.docc/Advanced/Using-a-Client-Certificate-with-URLSession.md`,
    /// written for a real app target's Signing & Capabilities tab), so `SecItemAdd` there fails
    /// with `errSecMissingEntitlement` before identity pairing is ever reached -- a genuinely
    /// different, still-open gap, confirmed directly on iOS/tvOS/watchOS Simulator CI runs.
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

    /// Positive control for the fix in `Internals.ExecutorIncompatibilityReason
    /// .multipleClientCertificatesUnderNetworkFramework`: pinned to `.nio` specifically (not
    /// `.nioTransportServices`), a real three-level client chain (root CA -> intermediate CA ->
    /// leaf) against a server that trusts only the root completes the handshake successfully --
    /// proving NIOSSL's own `TLSConfiguration.certificateChain` genuinely carries every
    /// certificate, which is exactly what the fix falls back to.
    ///
    /// The mirror case is `Internals.SecureConnection
    /// .makeLocalIdentityForNetworkFramework()`, which only ever builds its `SecIdentity` from
    /// the chain's first certificate -- confirmed end to end, not assumed, before this fix
    /// existed: the identical chain presented under `.nioTransportServices` instead failed the
    /// handshake with "-9831: unknown Cert Authority" (the server couldn't complete the chain
    /// from a leaf-only presentation, exactly as `openssl verify -CAfile root.crt leaf.crt`
    /// without `-untrusted intermediate.crt` also fails). `resolveExecutor()`/`requireExecutor(_:)`
    /// now steer a configuration like this away from `.nioTransportServices` automatically --
    /// see `dataTask_whenClientCertificateChainHasIntermediateAndNIOTransportServicesRequired_throwsExecutorError`
    /// right below for that half, and `InternalsSessionConfigurationExecutorTests+NIO`'s own
    /// `resolveExecutor_whenMultipleClientCertificatesSetAndNIOTransportServicesPreferred_fallsBackToNIO`
    /// for the resolution logic itself, proven without needing a live network round trip.
    ///
    /// Unlike `dataTask_whenCAEnabledUnderNIOTransportServices` above, this one needs no
    /// `withKnownIssue`/Keychain-entitlement caveat on iOS/tvOS/watchOS/Catalyst Simulator:
    /// `.requiredExecutor(.nio)` reads the identity straight off NIOSSL's own
    /// `TLSConfiguration.certificateChain`/`privateKey` -- no `SecIdentity`/Keychain round trip
    /// involved at all, so there's no entitlement gap to hit. Confirmed directly: CI failed with
    /// "Known issue was not recorded" on every Simulator platform when this was first wrapped in
    /// `withKnownIssue` (copied from the neighboring `.nioTransportServices`-requiring test,
    /// which does go through that round trip and genuinely needs the wrapper) -- the wrapped body
    /// unconditionally succeeded.
    @Test
    func dataTask_whenClientCertificateChainHasIntermediateUnderNIORequired_completesHandshake() async throws {
        // Given
        let server = Certificates().server()
        let root = CertificateResource("client_chain_root", format: .pem)
        let intermediate = CertificateResource("client_chain_intermediate", format: .pem)
        let leaf = CertificateResource("client_chain_leaf", format: .pem)

        let uri = "/" + UUID().uuidString

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8898,
                option: .client(root)
            )
        )

        let output = "Hello World"
        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: output), at: uri)
        defer { localServer.cleanup(at: uri) }

        // When / Then
        func verify() async throws {
            let data = try await DataTask {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer
                    .requiredExecutor(.nio)

                SecureConnection {
                    TrustRoots(server.certificateURL.absolutePath(percentEncoded: false))
                    RequestDL.Certificates {
                        Certificate(leaf.certificateURL.absolutePath(percentEncoded: false), format: .pem)
                        Certificate(
                            intermediate.certificateURL.absolutePath(percentEncoded: false),
                            format: .pem
                        )
                    }
                    PrivateKey(leaf.privateKeyURL.absolutePath(percentEncoded: false))
                }
                .verification(.fullVerification)
            }
            .extractPayload()
            .result()

            let result = try HTTPResult<String>(data)
            #expect(result.response == output)
        }

        try await verify()
    }

    /// The hard-pin counterpart to the fallback test above: `.requiredExecutor(.nioTransportServices)`
    /// must refuse a multi-certificate client chain outright -- the same way
    /// `dataTask_whenRequiredExecutorIsIncompatible_throwsActionableErrorBeforeAnyNetworkIO`
    /// already proves for an unrelated field -- rather than silently attempting the handshake and
    /// failing with an opaque `unknown_ca` TLS alert the way it used to.
    ///
    /// No `LocalServer` needed: `requireExecutor(_:)` throws before any client is built or
    /// network I/O starts.
    @Test
    func dataTask_whenClientCertificateChainHasIntermediateAndNIOTransportServicesRequired_throwsExecutorError()
        async throws
    {
        // Given
        let intermediate = CertificateResource("client_chain_intermediate", format: .pem)
        let leaf = CertificateResource("client_chain_leaf", format: .pem)

        let task = DataTask {
            BaseURL("localhost")

            Session()
                .requiredExecutor(.nioTransportServices)

            SecureConnection {
                RequestDL.Certificates {
                    Certificate(leaf.certificateURL.absolutePath(percentEncoded: false), format: .pem)
                    Certificate(intermediate.certificateURL.absolutePath(percentEncoded: false), format: .pem)
                }
                PrivateKey(leaf.privateKeyURL.absolutePath(percentEncoded: false))
            }
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
            #expect(error.requiredExecutor == .nioTransportServices)
            #expect(error.reasons == [.multipleClientCertificatesUnderNetworkFramework])
        }
    }

    /// Confirms (and regression-guards) the bug `Internals.Session.Configuration
    /// .networkFrameworkIncompatibilityReasons()`'s `.clientIdentityWithProxyUnderNetworkFramework`
    /// case now catches: `Internals.SecureConnection
    /// .makeTLSConfigurationByContext(isCompatibleWithNetworkFramework:)` deliberately leaves
    /// `certificateChain`/`privateKey` off the NIOSSL `TLSConfiguration` it builds whenever the
    /// configuration is Network.framework-compatible -- mTLS instead travels only through
    /// `tlsLocalIdentityNetworkFramework` (`makeLocalIdentityForNetworkFramework()`), the
    /// Network.framework-native channel.
    ///
    /// That's correct for a *direct* NIOTransportServices connection, which really does perform
    /// its TLS through Network.framework and therefore only ever consults
    /// `tlsLocalIdentityNetworkFramework`. It used to be wrong once a proxy was in the picture:
    /// AsyncHTTPClient performs TLS for a *proxied* HTTPS connection through NIOSSL even on a
    /// NIOTransportServices event loop (`setupTLSInProxyConnectionIfNeeded` in
    /// `HTTPConnectionPool+Factory.swift`, which reads `self.tlsConfiguration` -- the same NIOSSL
    /// `TLSConfiguration` `certificateChain`/`privateKey` were left off of), so with a client
    /// identity configured behind a proxy under `.nioTransportServices`, no client certificate
    /// ever reached the tunnel, and the server's mTLS verification -- which
    /// `LocalServer.TLSOption.client(_:)` performs -- failed. Confirmed directly: before this fix,
    /// this exact test failed with a connection reset.
    ///
    /// `.preferredExecutor`, not `.requiredExecutor`: this configuration must transparently fall
    /// back to `.nio` (where the identity *is* on the NIOSSL `TLSConfiguration`) rather than
    /// fail outright -- that's the whole point of the fix. The hard-pin case (`.requiredExecutor`
    /// correctly refusing this combination instead) is
    /// `dataTask_whenCAEnabledBehindProxyAndNIOTransportServicesRequired_throwsExecutorRequirementError`,
    /// right below.
    ///
    /// Unlike `dataTask_whenCAEnabledUnderNIOTransportServices` right above, this one needs no
    /// `withKnownIssue`/Keychain-entitlement caveat on iOS/tvOS/watchOS Simulator: the whole point
    /// of this test is that the configuration falls back to `.nio`, which reads the identity
    /// straight off NIOSSL's own `TLSConfiguration.certificateChain`/`privateKey` -- no
    /// `SecIdentity`/Keychain round trip involved at all, so there's no entitlement gap to hit
    /// here in the first place. Confirmed directly: CI failed with "Known issue was not
    /// recorded" on every Simulator platform when this was first wrapped in `withKnownIssue`
    /// (copied from the neighboring `.requiredExecutor(.nioTransportServices)` test, which does
    /// go through that Keychain round trip and genuinely needs the wrapper) -- the wrapped body
    /// unconditionally succeeded.
    @Test
    func dataTask_whenCAEnabledBehindProxyAndNIOTransportServicesPreferred_fallsBackToNIOAndCompletesHandshake()
        async throws
    {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let uri = "/" + UUID().uuidString

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8897,
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

        let proxy = try await LocalHTTPConnectProxy.start()
        defer {
            let proxy = proxy
            Task { try? await proxy.shutdown() }
        }

        let content = TestProperty {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer
                .preferredExecutor(.nioTransportServices)

            // Custom CONNECT headers, not just a plain `connection: .http` proxy: this rules
            // `.urlSession` out too (`.proxyConnectHeadersUnderURLSession`), which stays
            // genuinely compatible with a client identity + proxy and would otherwise win
            // `resolveExecutor()`'s default priority regardless of what this test is actually
            // trying to isolate. With `.urlSession` ruled out, resolution is a real contest
            // between `.nioTransportServices` (now incompatible, after the fix) and `.nio` (the
            // fallback) -- exactly the "proxy connect headers rule out .urlSession" scenario this
            // fix's own reachability analysis named.
            Proxy(host: proxy.host, port: proxy.port) {
                CustomHeader(name: "X-Test-Marker", value: "1")
            }

            SecureConnection {
                TrustRoots(server.certificateURL.absolutePath(percentEncoded: false))
                RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
                PrivateKey(client.privateKeyURL.absolutePath(percentEncoded: false))
            }
            .verification(.fullVerification)
        }

        // When / Then
        func verify() async throws {
            let data = try await DataTask { content }
                .extractPayload()
                .result()

            // Proves the request genuinely went through the tunnel, not straight to
            // `localServer` (which would trivially "succeed" for the wrong reason).
            #expect(proxy.connectAttempts.count >= 1)

            let result = try HTTPResult<String>(data)
            #expect(result.response == output)

            // Proves the fallback actually happened, not just that the handshake somehow
            // succeeded: this configuration must resolve to `.nio`, not `.nioTransportServices`
            // (`Internals.ClientManager.Client.nio` backs both, so that enum alone can't tell
            // them apart -- `resolveExecutor()`, the same call `RawTask`/`ClientManager` make,
            // can).
            let resolved = try await resolve(content)
            #expect(resolved.session.configuration.resolveExecutor() == .nio)
        }

        try await verify()
    }

    /// The hard-pin counterpart to the fallback test above: `.requiredExecutor(.nioTransportServices)`
    /// must refuse this same client-identity-behind-a-proxy combination outright, the same way
    /// `dataTask_whenRequiredExecutorIsIncompatible_throwsActionableErrorBeforeAnyNetworkIO`
    /// already proves for an unrelated field -- rather than silently attempting the handshake and
    /// failing with an opaque connection reset the way it used to.
    ///
    /// No `LocalServer`/`LocalHTTPConnectProxy` needed: `requireExecutor(_:)` throws before any
    /// client is built or network I/O starts.
    @Test
    func dataTask_whenCAEnabledBehindProxyAndNIOTransportServicesRequired_throwsExecutorRequirementError()
        async throws
    {
        // Given
        let client = Certificates().client()

        let task = DataTask {
            BaseURL("localhost")

            Session()
                .requiredExecutor(.nioTransportServices)

            Proxy(host: "127.0.0.1", port: 9999, connection: .http)

            SecureConnection {
                RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
                PrivateKey(client.privateKeyURL.absolutePath(percentEncoded: false))
            }
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
            #expect(error.requiredExecutor == .nioTransportServices)
            #expect(error.reasons == [.clientIdentityWithProxyUnderNetworkFramework])
        }
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

extension DataTaskTests {

    fileprivate final class PSKClientIdentityResolver: SSLPSKIdentityResolver {

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
}

#endif
