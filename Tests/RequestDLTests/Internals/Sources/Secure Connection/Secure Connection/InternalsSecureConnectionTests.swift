/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOSSL
import NIOCore
@testable import RequestDL

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
    func secureConnection_whenPrivateKey_shouldBeValid() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        let server = Certificates().server()
        let privateKeyPath = server.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        secureConnection.privateKey = .file(privateKeyPath)

        let sut = try secureConnection.build()

        // Then
        #expect(sut.tlsConfiguration.privateKey == .file(privateKeyPath))
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
            .ecdsaSecp384R1Sha384
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
            .ecdsaSecp384R1Sha384
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
            .TLS_RSA_WITH_AES_256_GCM_SHA384
        ]

        let cipherSuites = [
            "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
            "TLS_RSA_WITH_AES_256_GCM_SHA384"
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
}
