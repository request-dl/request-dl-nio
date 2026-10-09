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

    /// The client identity is offered per origin, not through the client-wide
    /// `TLSConfiguration`, so a server that redirects to another host that asks for a certificate
    /// is not handed it. `URLSession` answers such a challenge only for the host the request was
    /// made to. The two servers here differ in port, which is enough to be different origins.
    @Test
    func dataTask_whenRedirectedToAnotherOriginThatAsksForACertificate_doesNotPresentTheIdentity() async throws {
        // Given: a target that requires a client certificate, and an origin that redirects to it.
        let server = Certificates().server()
        let client = Certificates().client()

        let uri = "/" + UUID().uuidString

        let target = try await LocalServer(
            LocalServer.Configuration(host: "localhost", port: 8899, option: .client(client))
        )
        let origin = try await LocalServer(.standard)

        target.cleanup(at: uri)
        origin.cleanup(at: uri)
        defer {
            target.cleanup(at: uri)
            origin.cleanup(at: uri)
        }

        target.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: uri)
        origin.insert(
            LocalServer.ResponseConfiguration(
                status: .found,
                headers: ["Location": "https://\(target.baseURL)\(uri)"],
                data: Data()
            ),
            at: uri
        )

        func request(to server: LocalServer) -> DataTask<some Property> {
            DataTask {
                BaseURL(server.baseURL)
                Path(uri)

                Session.localServer
                    .requiredExecutor(.nio)

                SecureConnection {
                    TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
                    RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
                    PrivateKey(client.privateKeyURL.absolutePath(percentEncoded: false))
                }
                .verification(.fullVerification)
            }
        }

        // When / Then: reached through the redirect, it is another origin and gets none, so the
        // handshake it requires a certificate for fails.
        await #expect(throws: (any Error).self) {
            _ = try await request(to: origin).extractPayload().result()
        }

        // Control, after the redirect on purpose: an origin requested directly keeps getting the
        // identity from then on. Asked for directly, the target answers, so the failure above
        // was the identity and not the setup.
        let direct = try await request(to: target).extractPayload().result()
        #expect(try HTTPResult<String>(direct).response == "reached")

        _ = server
    }

    /// `certificateChain`/`privateKey` must not land on the `TLSConfiguration` that
    /// AsyncHTTPClient's NIOTransportServices bridge also reads, which `preconditionFailure`s the
    /// instant either is non-empty, regardless of the Network.framework-native identity also
    /// being supplied correctly via `tlsLocalIdentityNetworkFramework`
    /// (`Internals.SecureConnection.build(isCompatibleWithNetworkFramework:)`).
    ///
    /// Reachable in practice via `enableNetworkFramework(true)`/
    /// `preferredExecutor(.nioTransportServices)`/this test's own
    /// `requiredExecutor(.nioTransportServices)` any time mTLS is also configured, since mTLS is
    /// genuinely supported there, just through a different channel.
    ///
    /// The Keychain round trip this needs succeeds on real macOS (bare `swift test` or an Xcode-run
    /// macOS test bundle) because `Internals.RawBytesIdentityBuilder .makeIdentity(_:_:)` sets
    /// `kSecAttrApplicationLabel` correctly. Every other Apple platform's Simulator, reached only
    /// via `xcodebuild test` against SwiftPM's auto-generated scheme, has no `.entitlements` file
    /// to add Keychain Sharing to at all (there is nowhere in a `Package.swift`-only project to
    /// configure one; see
    /// `Sources/RequestDL/Documentation.docc/Advanced/Using-a-Client-Certificate-with-URLSession.md`,
    /// written for a real app target's Signing & Capabilities tab), so `SecItemAdd` there fails
    /// with `errSecMissingEntitlement` before identity pairing is ever reached.
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

    /// Positive control for `Internals.ExecutorIncompatibilityReason
    /// .multipleClientCertificatesUnderNetworkFramework`: pinned to `.nio` specifically (not
    /// `.nioTransportServices`), a real three-level client chain (root CA -> intermediate CA ->
    /// leaf) against a server that trusts only the root completes the handshake successfully,
    /// proving NIOSSL's own `TLSConfiguration.certificateChain` carries every certificate, which
    /// is what a configuration like this falls back to.
    ///
    /// The mirror case is `Internals.SecureConnection.makeLocalIdentityForNetworkFramework()`,
    /// which only ever builds its `SecIdentity` from the chain's first certificate: the identical
    /// chain presented under `.nioTransportServices` fails the handshake with "-9831: unknown Cert
    /// Authority" (the server can't complete the chain from a leaf-only presentation, exactly as
    /// `openssl verify -CAfile root.crt leaf.crt` without `-untrusted intermediate.crt` also
    /// fails). `resolveExecutor()`/`requireExecutor(_:)` steer a configuration like this away from
    /// `.nioTransportServices` automatically. See
    /// `dataTask_whenClientCertificateChainHasIntermediateAndNIOTransportServicesRequired_throwsExecutorError`
    /// right below for that half, and `InternalsSessionConfigurationExecutorTests+NIO`'s own
    /// `resolveExecutor_whenMultipleClientCertificatesSetAndNIOTransportServicesPreferred_fallsBackToNIO`
    /// for the resolution logic itself, proven without needing a live network round trip.
    ///
    /// Unlike `dataTask_whenCAEnabledUnderNIOTransportServices` above, this one needs no
    /// `withKnownIssue`/Keychain-entitlement caveat on iOS/tvOS/watchOS/Catalyst Simulator:
    /// `.requiredExecutor(.nio)` reads the identity straight off NIOSSL's own
    /// `TLSConfiguration.certificateChain`/`privateKey`, with no `SecIdentity`/Keychain round
    /// trip involved, so there's no entitlement gap to hit. Wrapping its body in
    /// `withKnownIssue` would fail with "Known issue was not recorded", since the body
    /// unconditionally succeeds.
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

    /// The hard-pin counterpart to the fallback test above:
    /// `.requiredExecutor(.nioTransportServices)` must refuse a multi-certificate client chain
    /// outright, the same way
    /// `dataTask_whenRequiredExecutorIsIncompatible_throwsActionableErrorBeforeAnyNetworkIO`
    /// already proves for an unrelated field, rather than silently attempting the handshake and
    /// failing with an opaque `unknown_ca` TLS alert.
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

    /// `Internals.Session.Configuration.networkFrameworkIncompatibilityReasons()`'s
    /// `.clientIdentityWithProxyUnderNetworkFramework` case catches this:
    /// `Internals.SecureConnection
    /// .makeTLSConfigurationByContext(isCompatibleWithNetworkFramework:)` deliberately leaves
    /// `certificateChain`/`privateKey` off the NIOSSL `TLSConfiguration` it builds whenever the
    /// configuration is Network.framework-compatible, since mTLS instead travels only through
    /// `tlsLocalIdentityNetworkFramework` (`makeLocalIdentityForNetworkFramework()`), the
    /// Network.framework-native channel.
    ///
    /// That's correct for a *direct* NIOTransportServices connection, which really does perform
    /// its TLS through Network.framework and therefore only ever consults
    /// `tlsLocalIdentityNetworkFramework`. It is wrong once a proxy is in the picture:
    /// AsyncHTTPClient performs TLS for a *proxied* HTTPS connection through NIOSSL even on a
    /// NIOTransportServices event loop (`setupTLSInProxyConnectionIfNeeded` in
    /// `HTTPConnectionPool+Factory.swift`, which reads `self.tlsConfiguration`, the same NIOSSL
    /// `TLSConfiguration` `certificateChain`/`privateKey` were left off of), so with a client
    /// identity configured behind a proxy under `.nioTransportServices`, no client certificate
    /// would reach the tunnel, and the server's mTLS verification, which
    /// `LocalServer.TLSOption.client(_:)` performs, would fail with a connection reset.
    ///
    /// `.preferredExecutor`, not `.requiredExecutor`: this configuration must transparently fall
    /// back to `.nio` (where the identity *is* on the NIOSSL `TLSConfiguration`) rather than fail
    /// outright. The hard-pin case (`.requiredExecutor` correctly refusing this combination
    /// instead) is
    /// `dataTask_whenCAEnabledBehindProxyAndNIOTransportServicesRequired_throwsExecutorRequirementError`,
    /// right below.
    ///
    /// Unlike `dataTask_whenCAEnabledUnderNIOTransportServices` right above, this one needs no
    /// `withKnownIssue`/Keychain-entitlement caveat on iOS/tvOS/watchOS Simulator: the
    /// configuration falls back to `.nio`, which reads the identity straight off NIOSSL's own
    /// `TLSConfiguration.certificateChain`/`privateKey`, with no `SecIdentity`/Keychain round
    /// trip involved, so there's no entitlement gap to hit. Wrapping its body in `withKnownIssue`
    /// would fail with "Known issue was not recorded", since the body unconditionally succeeds.
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
            // between `.nioTransportServices` (incompatible) and `.nio` (the fallback), the "proxy
            // connect headers rule out .urlSession" scenario.
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
            // them apart; `resolveExecutor()`, the same call `RawTask`/`ClientManager` make,
            // can).
            let resolved = try await resolve(content)
            #expect(resolved.session.configuration.resolveExecutor() == .nio)
        }

        try await verify()
    }

    /// The hard-pin counterpart to the fallback test above:
    /// `.requiredExecutor(.nioTransportServices)` must refuse this same
    /// client-identity-behind-a-proxy combination outright, the same way
    /// `dataTask_whenRequiredExecutorIsIncompatible_throwsActionableErrorBeforeAnyNetworkIO`
    /// already proves for an unrelated field, rather than silently attempting the handshake and
    /// failing with an opaque connection reset.
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

    /// The gap `Internals.NIOTrustEvaluator` closes: `additionalTrustRoots` alone, with no SPKI
    /// pinning, must not be silently ignored under Network.framework.
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

            // The default connect timeout is sized for a quiet machine; on a starved simulator the
            // handshake alone can outlast it.
            Timeout(.seconds(simulatorAffectedConnectTimeoutSeconds), for: .connect)

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

    /// The gap `Internals.NIOTrustEvaluator` closes: `.noHostnameVerification` alone must not
    /// trap under Network.framework (AsyncHTTPClient's own `precondition`, unless a custom
    /// verification callback is installed).
    ///
    /// Paired with
    /// `dataTask_whenNoHostnameVerificationSetWithoutTrustRoots_stillRejectsUntrustedCertificate`
    /// below (chain trust still enforced with no `TrustRoots`), this proves it skips exactly the
    /// hostname check and nothing more. `Internals.NIOTrustEvaluator` swaps the `SecTrust`'s policy
    /// for a hostname-less one but still anchors it on `TrustRoots`/`additionalTrustRoots` and
    /// still evaluates the chain.
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

            // See `dataTask_whenAdditionalTrustRootsSetAndNIOTransportServicesRequired_...`.
            Timeout(.seconds(simulatorAffectedConnectTimeoutSeconds), for: .connect)

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
