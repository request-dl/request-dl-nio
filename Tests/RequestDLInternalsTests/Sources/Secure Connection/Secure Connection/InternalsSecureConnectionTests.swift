//
// See LICENSE for this package's licensing information.
//

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

struct InternalsSecureConnectionTests {

    @Test
    func secureConnection_whenDefaultTrustNotSet_shouldBeFalse() async throws {
        // Given
        let secureConnection = Internals.SecureConnection()
        // Then
        #expect(!secureConnection.useDefaultTrustRoots)
    }

    @Test
    func secureConnection_whenSetDefaultTrust() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        // When
        secureConnection.useDefaultTrustRoots = true

        // Then
        #expect(secureConnection.useDefaultTrustRoots)
    }

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
        let certificateVerification: NIOSSL.CertificateVerification = .noHostnameVerification

        // When
        secureConnection.certificateVerification = certificateVerification

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.certificateVerification == certificateVerification)
    }

    @Test
    func secureConnection_whenSigningSignatureAlgorithms_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        let signatureAlgorithms: [NIOSSL.SignatureAlgorithm] = [
            .ecdsaSecp256R1Sha256,
            .ecdsaSecp384R1Sha384,
        ]

        // When
        secureConnection.signingSignatureAlgorithms = signatureAlgorithms

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.signingSignatureAlgorithms == signatureAlgorithms)
    }

    @Test
    func secureConnection_whenVerifySignatureAlgorithms_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        let signatureAlgorithms: [NIOSSL.SignatureAlgorithm] = [
            .ecdsaSecp256R1Sha256,
            .ecdsaSecp384R1Sha384,
        ]

        // When
        secureConnection.verifySignatureAlgorithms = signatureAlgorithms

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.verifySignatureAlgorithms == signatureAlgorithms)
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
        let renegotiationSupport: NIORenegotiationSupport = .once

        // When
        secureConnection.renegotiationSupport = renegotiationSupport

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.renegotiationSupport == renegotiationSupport)
    }

    @Test
    func secureConnection_whenShutdownTimeout_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        let timeout = NIOCore.TimeAmount.seconds(50)

        // When
        secureConnection.shutdownTimeout = timeout

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.shutdownTimeout == timeout)
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

        let minimumVersion = TLSVersion.tlsv11
        let maximumVersion = TLSVersion.tlsv13

        // When
        secureConnection.minimumTLSVersion = minimumVersion
        secureConnection.maximumTLSVersion = maximumVersion

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.minimumTLSVersion == minimumVersion)
        #expect(sut.tlsConfiguration.maximumTLSVersion == maximumVersion)
    }

    @Test
    func secureConnection_whenCipherSuites_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        let cipherSuitesValues: [NIOTLSCipher] = [
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
        #expect(sut.tlsConfiguration.cipherSuiteValues == cipherSuitesValues)
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

    @Test
    func secureConnection_whenEquals() async throws {
        // Given
        let lhs = Internals.SecureConnection()
        let rhs = Internals.SecureConnection()

        // Then
        #expect(lhs == rhs)
    }

    @Test
    func secureConnection_whenNotEquals() async throws {
        // Given
        var lhs = Internals.SecureConnection()
        var rhs = Internals.SecureConnection()

        // When
        lhs.maximumTLSVersion = .tlsv12
        rhs.maximumTLSVersion = .tlsv13

        // Then
        #expect(lhs != rhs)
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

    @Test
    func secureConnection_whenDefault_isCompatibleWithNetworkFramework() async throws {
        // Given
        let secureConnection = Internals.SecureConnection()

        // Then
        #if canImport(Darwin)
        #expect(secureConnection.isCompatibleWithNetworkFramework)
        #else
        #expect(!secureConnection.isCompatibleWithNetworkFramework)
        #endif
    }

    /// Regression coverage for the fields AsyncHTTPClient's NIOTransportServices bridge either
    /// traps on (`keyLogger`, `.noHostnameVerification` -- unless a custom verification callback
    /// is also installed, which none of these cases do) or silently drops (everything else here,
    /// when SPKI pinning isn't also configured -- see `additionalTrustRootsUnderNetworkFramework`'s
    /// doc comment) when running on Network.framework. Each one must flip
    /// `isCompatibleWithNetworkFramework` to `false` so the caller falls back to plain NIO instead
    /// of crashing or losing the setting without any signal. `certificateChain`/`privateKey`
    /// (mTLS) and `tlsPins` (SPKI pinning) are deliberately *not* in this list any more -- see
    /// `secureConnection_whenNetworkFrameworkReachableFieldSet_remainsCompatible` below.
    @Test(
        arguments: [
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.certificateVerification = .noHostnameVerification
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.additionalTrustRoots = [.file("/dev/null")]
            },
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
                secureConnection.shutdownTimeout = .seconds(5)
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

    /// mTLS (`certificateChain`/`privateKey`) and SPKI pinning (`tlsPins`) both reach
    /// Network.framework now, through `tlsLocalIdentityNetworkFramework` and
    /// `tlsCustomVerificationNetworkFramework` respectively (AsyncHTTPClient fork, 1.38.0+) --
    /// mirrors `secureConnection_whenURLSessionReachableFieldSet_remainsCompatible` below, but for
    /// the Network.framework-facing reason list.
    @Test(
        arguments: [
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.certificateChain = .certificates([])
                secureConnection.privateKey = .privateKey(.init([], format: .pem))
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.tlsPins = [.init(source: .rawData(.init()), algorithm: SHA256.self)]
            },
        ] as [@Sendable (inout Internals.SecureConnection) -> Void]
    )
    func secureConnection_whenNetworkFrameworkReachableFieldSet_remainsCompatible(
        _ mutate: @Sendable (inout Internals.SecureConnection) -> Void
    ) async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        // When
        mutate(&secureConnection)

        // Then -- `networkFrameworkIncompatibilityReasons()` (the platform-independent logic this
        // test actually exercises), not `isCompatibleWithNetworkFramework` (which is unconditionally
        // `false` off Darwin regardless of reasons, since Network.framework doesn't exist there at
        // all -- see `secureConnection_whenDefault_isCompatibleWithNetworkFramework` above).
        #expect(secureConnection.networkFrameworkIncompatibilityReasons().isEmpty)
    }

    @Test
    func secureConnection_whenDefault_urlSessionIncompatibilityReasonsIsEmpty() async throws {
        // Given
        let secureConnection = Internals.SecureConnection()

        // Then
        #expect(secureConnection.urlSessionIncompatibilityReasons().isEmpty)
    }

    /// Mirrors `secureConnection_whenNetworkFrameworkUnsupportedFieldSet_isIncompatible` above,
    /// but for the URLSession-facing reason list -- deliberately a *different* field set, since
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
                secureConnection.shutdownTimeout = .seconds(5)
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

    /// Executor compatibility is not a strict hierarchy, made concrete: these four fields are
    /// excluded from `networkFrameworkIncompatibilityReasons()`'s counterpart list but reachable under
    /// URLSession (via a Keychain round-trip for the identity fields, `SecTrust`/`SecPolicy` for
    /// trust roots and hostname verification), so they must never appear in the URLSession
    /// reason list.
    @Test(
        arguments: [
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.certificateVerification = .noHostnameVerification
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.additionalTrustRoots = [.file("/dev/null")]
            },
        ] as [@Sendable (inout Internals.SecureConnection) -> Void]
    )
    func secureConnection_whenURLSessionReachableFieldSet_remainsCompatible(
        _ mutate: @Sendable (inout Internals.SecureConnection) -> Void
    ) async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        // When
        mutate(&secureConnection)

        // Then
        #expect(secureConnection.urlSessionIncompatibilityReasons().isEmpty)
    }

    @Test
    func secureConnection_whenKeyLoggerSet_urlSessionIncompatibilityReasonsContainsKeyLogger() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.keyLogger = KeyLogger { _ in }

        // Then
        #expect(secureConnection.urlSessionIncompatibilityReasons().contains(.keyLogger))
    }

    /// Regression coverage: `build()` used to call `makeLocalIdentityForNetworkFramework()` -- a
    /// Keychain round-trip -- unconditionally on Darwin whenever both `certificateChain`/
    /// `privateKey` were configured, even for a caller that was never going to run over
    /// Network.framework at all. That meant configuring mTLS for `.urlSession`/
    /// `.nioTransportServices` silently broke a `.nio`-pinned request too, on any process without
    /// Keychain Sharing entitlement (e.g. this SwiftPM test harness) -- see
    /// `DataTaskTests.dataTask_whenCAEnabled()`, which pins `.requiredExecutor(.nio)` specifically
    /// to avoid this and used to hit it anyway.
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

        // Then -- completes without ever attempting the Keychain round-trip, even on a machine
        // with no Keychain Sharing entitlement at all. `tlsConfiguration.certificateChain` still
        // carries the mTLS cert, proving `build()` did real work rather than short-circuiting.
        #expect(!sut.tlsConfiguration.certificateChain.isEmpty)
        #if canImport(Darwin)
        #expect(sut.localIdentityHandle == nil)
        #endif
    }
}
