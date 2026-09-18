//
// See LICENSE for this package's licensing information.
//

// Every test here either calls `secureConnection.build()` or touches `keyLogger`/
// `pskIdentityResolver`/`pskHint`; all only exist under `canImport(NIOCore)`. See the main
// declaration's own doc comment, in `InternalsSecureConnectionTests.swift`.
#if canImport(NIOCore)

import Crypto
import NIOCore
import NIOSSL
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
import NIOFoundationEssentialsCompat
#else
import struct Foundation.Data
#endif

extension InternalsSecureConnectionTests {

    @Test
    func secureConnection_whenTrustRoots_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        let server = Certificates().server()
        let certificatePath = server.certificateURL.absolutePath(percentEncoded: false)

        // When
        secureConnection.trustRoots = .file(certificatePath)

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.trustRoots == .file(certificatePath))
    }

    @Test
    func secureConnection_whenAdditionalTrustRoots_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        let server = Certificates().server()
        let certificatePath = server.certificateURL.absolutePath(percentEncoded: false)

        // When
        secureConnection.additionalTrustRoots = [.file(certificatePath)]

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.additionalTrustRoots == [.file(certificatePath)])
    }

    @Test
    func secureConnection_whenCertificateVerification_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        let certificateVerification: Internals.CertificateVerification = .noHostnameVerification

        // When
        secureConnection.certificateVerification = certificateVerification

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.certificateVerification == certificateVerification.build())
    }

    @Test
    func secureConnection_whenSigningSignatureAlgorithms_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        let signatureAlgorithms: [Internals.SignatureAlgorithm] = [
            .ecdsaSecp256R1Sha256,
            .ecdsaSecp384R1Sha384,
        ]

        // When
        secureConnection.signingSignatureAlgorithms = signatureAlgorithms

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.signingSignatureAlgorithms == signatureAlgorithms.map { $0.build() })
    }

    @Test
    func secureConnection_whenVerifySignatureAlgorithms_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        let signatureAlgorithms: [Internals.SignatureAlgorithm] = [
            .ecdsaSecp256R1Sha256,
            .ecdsaSecp384R1Sha384,
        ]

        // When
        secureConnection.verifySignatureAlgorithms = signatureAlgorithms

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.verifySignatureAlgorithms == signatureAlgorithms.map { $0.build() })
    }

    @Test
    func secureConnection_whenSendCANameList_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        let sendCANameList = true

        // When
        secureConnection.sendCANameList = sendCANameList

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.sendCANameList == sendCANameList)
    }

    @Test
    func secureConnection_whenRenegotiationSupport_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        let renegotiationSupport: Internals.RenegotiationSupport = .once

        // When
        secureConnection.renegotiationSupport = renegotiationSupport

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.renegotiationSupport == renegotiationSupport.build())
    }

    @Test
    func secureConnection_whenShutdownTimeout_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        let timeout: Int64 = 50_000_000_000

        // When
        secureConnection.shutdownTimeout = timeout

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.shutdownTimeout == .nanoseconds(timeout))
    }

    @Test
    func secureConnection_whenPSKHint_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        let pskHint = "example.com"

        // When
        secureConnection.pskHint = pskHint

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.pskHint == pskHint)
    }

    @Test
    func secureConnection_whenApplicationProtocols_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        let applicationProtocolos = ["h2"]

        // When
        secureConnection.applicationProtocols = applicationProtocolos

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.applicationProtocols == applicationProtocolos)
    }

    @Test
    func secureConnection_whenTLSVersion_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        let minimumVersion = Internals.TLSVersion.tlsv11
        let maximumVersion = Internals.TLSVersion.tlsv13

        // When
        secureConnection.minimumTLSVersion = minimumVersion
        secureConnection.maximumTLSVersion = maximumVersion

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.minimumTLSVersion == minimumVersion.build())
        #expect(sut.tlsConfiguration.maximumTLSVersion == maximumVersion.build())
    }

    @Test
    func secureConnection_whenCipherSuites_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        let cipherSuitesValues: [Internals.TLSCipher] = [
            .TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA,
            .TLS_RSA_WITH_AES_256_GCM_SHA384,
        ]

        let cipherSuites = [
            "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
            "TLS_RSA_WITH_AES_256_GCM_SHA384",
        ].joined(separator: ":")

        // When
        secureConnection.cipherSuites = cipherSuites
        secureConnection.cipherSuiteValues = cipherSuitesValues

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.cipherSuites == cipherSuites)
        #expect(sut.tlsConfiguration.cipherSuiteValues == cipherSuitesValues.map { $0.build() })
    }

    @Test
    func secureConnection_whenClient_shouldBeValid() async throws {
        // Given
        let secureConnection = Internals.SecureConnection()
        let configuration: TLSConfiguration = .clientDefault

        // When
        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.certificateChain == configuration.certificateChain)
        #expect(sut.tlsConfiguration.certificateVerification == configuration.certificateVerification)
        #expect(sut.tlsConfiguration.trustRoots == configuration.trustRoots)
        #expect(sut.tlsConfiguration.additionalTrustRoots == configuration.additionalTrustRoots)
        #expect(sut.tlsConfiguration.privateKey == configuration.privateKey)
        #expect(sut.tlsConfiguration.signingSignatureAlgorithms == configuration.signingSignatureAlgorithms)
        #expect(sut.tlsConfiguration.verifySignatureAlgorithms == configuration.verifySignatureAlgorithms)
        #expect(sut.tlsConfiguration.sendCANameList == configuration.sendCANameList)
        #expect(sut.tlsConfiguration.renegotiationSupport == configuration.renegotiationSupport)
        #expect(sut.tlsConfiguration.shutdownTimeout == configuration.shutdownTimeout)
        #expect(sut.tlsConfiguration.pskHint == configuration.pskHint)
        #expect(sut.tlsConfiguration.applicationProtocols == configuration.applicationProtocols)
        #expect(sut.tlsConfiguration.keyLogCallback == nil)
        #expect(sut.tlsConfiguration.pskClientCallback == nil)
        #expect(sut.tlsConfiguration.pskServerCallback == nil)
        #expect(sut.tlsConfiguration.minimumTLSVersion == configuration.minimumTLSVersion)
        #expect(sut.tlsConfiguration.maximumTLSVersion == configuration.maximumTLSVersion)
        #expect(sut.tlsConfiguration.cipherSuites == configuration.cipherSuites)
        #expect(sut.tlsConfiguration.cipherSuiteValues == configuration.cipherSuiteValues)
    }
}

extension InternalsSecureConnectionTests {

    private final class KeyLogger: SSLKeyLogger {

        private let data: @Sendable (Data?) -> Void

        init(_ data: @escaping @Sendable (Data?) -> Void) {
            self.data = data
        }

        func callAsFunction(_ bytes: ByteBuffer) {
            data(bytes.getData(at: .zero, length: bytes.readableBytes))
        }
    }

    @Test
    func secureConnection_whenKeyLog_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        let data = Data("Hello World".utf8)

        // When
        secureConnection.keyLogger = KeyLogger {
            #expect($0 == data)
        }

        let sut = try secureConnection.build()

        // Then
        sut.tlsConfiguration.keyLogCallback?(.init(data: data))
    }

    @Test
    func secureConnection_whenKeyLoggerSet_urlSessionIncompatibilityReasonsContainsKeyLogger() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.keyLogger = KeyLogger { _ in }

        // Then
        #expect(secureConnection.urlSessionIncompatibilityReasons().contains(.keyLogger))
    }
}

extension InternalsSecureConnectionTests {

    private final class ClientResolver: SSLPSKIdentityResolver {

        func callAsFunction(_ context: PSKClientContext) throws -> PSKClientIdentityResponse {
            let hint = context.hint ?? "pskHint"
            return .init(
                key: .init(Data(hint.utf8)),
                identity: hint
            )
        }
    }

    @Test
    func secureConnection_whenPSKClient_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        let identity = "apple.com"
        let resolver = ClientResolver()

        // When
        secureConnection.pskIdentityResolver = resolver

        let sut = try secureConnection.build()
        let result = try sut.tlsConfiguration.pskClientProvider.map {
            try $0(.init(hint: identity, maxPSKLength: 1_000))
        }

        // Then

        #expect(result?.identity == identity)

        #expect(result.map { Data($0.key) } == Data(identity.utf8))
    }

    /// Regression coverage for the fields AsyncHTTPClient's NIOTransportServices bridge either
    /// traps on (`keyLogger`, with no custom verification callback able to work around it, unlike
    /// `.noHostnameVerification`, see the doc comment below) or silently drops (everything else
    /// here; they're read from the built `TLSConfiguration` and then never looked at again) when
    /// running on Network.framework.
    ///
    /// Each one must flip `isCompatibleWithNetworkFramework` to `false` so the caller falls back
    /// to plain NIO instead of crashing or losing the setting without any signal.
    /// `certificateChain`/`privateKey` (mTLS), `tlsPins` (SPKI pinning), `additionalTrustRoots`,
    /// and `.noHostnameVerification` are deliberately *not* in this list; see
    /// `secureConnection_whenNetworkFrameworkReachableFieldSet_remainsCompatible` (main file).
    @Test(
        arguments: [
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.renegotiationSupport = .once
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.signingSignatureAlgorithms = [.ecdsaSecp256R1Sha256]
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.verifySignatureAlgorithms = [.ecdsaSecp256R1Sha256]
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.sendCANameList = true
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.shutdownTimeout = 5_000_000_000
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.pskHint = "hint"
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.cipherSuiteValues = [.TLS_AES_128_GCM_SHA256]
            },
        ] as [@Sendable (inout Internals.SecureConnection) -> Void]
    )
    func secureConnection_whenNetworkFrameworkUnsupportedFieldSet_isIncompatible(
        _ mutate: @Sendable (inout Internals.SecureConnection) -> Void
    ) async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        // When
        mutate(&secureConnection)

        // Then
        #expect(!secureConnection.isCompatibleWithNetworkFramework)
    }

    /// Mirrors `secureConnection_whenNetworkFrameworkUnsupportedFieldSet_isIncompatible` above,
    /// but for the URLSession-facing reason list: deliberately a *different* field set, since
    /// the two executors aren't a strict hierarchy of each other.
    @Test(
        arguments: [
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.signingSignatureAlgorithms = [.ecdsaSecp256R1Sha256]
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.verifySignatureAlgorithms = [.ecdsaSecp256R1Sha256]
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.sendCANameList = true
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.renegotiationSupport = .once
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.shutdownTimeout = 5_000_000_000
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.pskHint = "hint"
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.cipherSuiteValues = [.TLS_AES_128_GCM_SHA256]
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.cipherSuites = "DEFAULT"
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.maximumTLSVersion = .tlsv12
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.applicationProtocols = ["h2"]
            },
        ] as [@Sendable (inout Internals.SecureConnection) -> Void]
    )
    func secureConnection_whenURLSessionUnsupportedFieldSet_isIncompatible(
        _ mutate: @Sendable (inout Internals.SecureConnection) -> Void
    ) async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        // When
        mutate(&secureConnection)

        // Then
        #expect(!secureConnection.urlSessionIncompatibilityReasons().isEmpty)
    }

    /// Regression coverage: `build()` used to call `makeLocalIdentityForNetworkFramework()`, a
    /// Keychain round-trip, unconditionally on Darwin whenever both `certificateChain`/
    /// `privateKey` were configured, even for a caller that was never going to run over
    /// Network.framework at all. That meant configuring mTLS for `.urlSession`/
    /// `.nioTransportServices` silently broke a `.nio`-pinned request too, on any process without
    /// Keychain Sharing entitlement (e.g. this SwiftPM test harness).
    ///
    /// See `DataTaskTests.dataTask_whenCAEnabled()`, which pins `.requiredExecutor(.nio)`
    /// specifically to avoid this and used to hit it anyway.
    @Test
    func secureConnection_whenMTLSConfiguredButNetworkFrameworkNotNeeded_skipsKeychainIdentityBuild() async throws {
        // Given
        let client = Certificates().client()

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file(client.certificateURL.absolutePath(percentEncoded: false))
        secureConnection.privateKey = .privateKey(
            .init(client.privateKeyURL.absolutePath(percentEncoded: false), format: .pem)
        )

        // When
        let sut = try secureConnection.build(isCompatibleWithNetworkFramework: false)

        // Then: completes without ever attempting the Keychain round-trip, even on a machine
        // with no Keychain Sharing entitlement at all. `tlsConfiguration.certificateChain` still
        // carries the mTLS cert, proving `build()` did real work rather than short-circuiting.
        #expect(!sut.tlsConfiguration.certificateChain.isEmpty)
        #if canImport(Darwin)
        #expect(sut.localIdentityHandle == nil)
        #endif
    }

    /// Regression coverage for a crash: `TLSConfiguration.getNWProtocolTLSOptions()`
    /// (AsyncHTTPClient's NIOTransportServices bridge) `preconditionFailure`s the instant
    /// `certificateChain`/`privateKey` is non-empty, unconditionally, so leaving either set,
    /// even alongside a correctly-built `localIdentityHandle`, would crash the process the moment
    /// this configuration actually ran over `.nioTransportServices`.
    ///
    /// `build()` bundles that `TLSConfiguration` and the Network.framework identity into one
    /// throwing call, so this can't inspect the former without the latter's Keychain round-trip
    /// also succeeding, a known gap on this bare SwiftPM test harness (see
    /// `InternalsClientIdentityDescriptorTests`) unrelated to what's actually being checked here,
    /// hence the `withKnownIssue` wrapper.
    @Test
    func secureConnection_whenMTLSConfiguredAndNetworkFrameworkNeeded_omitsRawCertificateChainFromTLSConfiguration()
        async throws
    {
        // Given
        let client = Certificates().client()

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file(client.certificateURL.absolutePath(percentEncoded: false))
        secureConnection.privateKey = .privateKey(
            .init(client.privateKeyURL.absolutePath(percentEncoded: false), format: .pem)
        )

        // When / Then
        func verify() throws {
            let sut = try secureConnection.build(isCompatibleWithNetworkFramework: true)

            #expect(sut.tlsConfiguration.certificateChain.isEmpty)
            #expect(sut.tlsConfiguration.privateKey == nil)
        }

        // The Keychain round-trip this "known issue" is about only happens inside
        // `#if canImport(Darwin)` code (`makeLocalIdentityForNetworkFramework()`); off Darwin,
        // `build(isCompatibleWithNetworkFramework:)` never touches the Keychain at all, so `verify()`
        // succeeds outright there and `withKnownIssue` would fail the test for "not" hitting an
        // issue that was never reachable off Darwin to begin with.
        #if canImport(Darwin)
        await withKnownIssue(
            "this SwiftPM test harness has no Keychain Sharing entitlement on any platform; see RequestConfigurationURLSessionClientMTLSTests's type doc comment"
        ) {
            try verify()
        }
        #else
        try verify()
        #endif
    }
}

#endif
