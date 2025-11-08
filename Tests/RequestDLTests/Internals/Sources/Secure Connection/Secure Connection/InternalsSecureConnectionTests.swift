/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOSSL
import NIOCore
@testable import RequestDL

struct InternalsSecureConnectionTests {

    var secureConnection: Internals.SecureConnection?

    override func setUp() async throws {
        try await super.setUp()
        secureConnection = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        secureConnection = nil
    }

    @Test
    func secureConnection_whenDefaultTrustNotSet_shouldBeFalse() async throws {
        // Given
        let secureConnection = try #require(secureConnection)
        // Then
        #expect(!secureConnection.useDefaultTrustRoots)
    }

    @Test
    func secureConnection_whenSetDefaultTrust() async throws {
        // Given
        var secureConnection = try #require(secureConnection)

        // When
        secureConnection.useDefaultTrustRoots = true

        // Then
        #expect(secureConnection.useDefaultTrustRoots)
    }

    @Test
    func secureConnection_whenTrustRoots_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)

        let server = Certificates().server()
        let certificatePath = server.certificateURL.absolutePath(percentEncoded: false)

        // When
        secureConnection.trustRoots = .file(certificatePath)

        let sut = try secureConnection.build()

        // Then
        #expect(sut.trustRoots == .file(certificatePath))
    }

    @Test
    func secureConnection_whenAdditionalTrustRoots_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)

        let server = Certificates().server()
        let certificatePath = server.certificateURL.absolutePath(percentEncoded: false)

        // When
        secureConnection.additionalTrustRoots = [.file(certificatePath)]

        let sut = try secureConnection.build()

        // Then
        #expect(sut.additionalTrustRoots == [.file(certificatePath)])
    }

    @Test
    func secureConnection_whenPrivateKey_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)

        let server = Certificates().server()
        let privateKeyPath = server.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        secureConnection.privateKey = .file(privateKeyPath)

        let sut = try secureConnection.build()

        // Then
        #expect(sut.privateKey == .file(privateKeyPath))
    }

    @Test
    func secureConnection_whenCertificateVerification_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)
        let certificateVerification: NIOSSL.CertificateVerification = .noHostnameVerification

        // When
        secureConnection.certificateVerification = certificateVerification

        let sut = try secureConnection.build()

        // Then
        #expect(sut.certificateVerification == certificateVerification)
    }

    @Test
    func secureConnection_whenSigningSignatureAlgorithms_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)

        let signatureAlgorithms: [NIOSSL.SignatureAlgorithm] = [
            .ecdsaSecp256R1Sha256,
            .ecdsaSecp384R1Sha384
        ]

        // When
        secureConnection.signingSignatureAlgorithms = signatureAlgorithms

        let sut = try secureConnection.build()

        // Then
        #expect(sut.signingSignatureAlgorithms == signatureAlgorithms)
    }

    @Test
    func secureConnection_whenVerifySignatureAlgorithms_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)

        let signatureAlgorithms: [NIOSSL.SignatureAlgorithm] = [
            .ecdsaSecp256R1Sha256,
            .ecdsaSecp384R1Sha384
        ]

        // When
        secureConnection.verifySignatureAlgorithms = signatureAlgorithms

        let sut = try secureConnection.build()

        // Then
        #expect(sut.verifySignatureAlgorithms == signatureAlgorithms)
    }

    @Test
    func secureConnection_whenSendCANameList_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)
        let sendCANameList = true

        // When
        secureConnection.sendCANameList = sendCANameList

        let sut = try secureConnection.build()

        // Then
        #expect(sut.sendCANameList == sendCANameList)
    }

    @Test
    func secureConnection_whenRenegotiationSupport_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)
        let renegotiationSupport: NIORenegotiationSupport = .once

        // When
        secureConnection.renegotiationSupport = renegotiationSupport

        let sut = try secureConnection.build()

        // Then
        #expect(sut.renegotiationSupport == renegotiationSupport)
    }

    @Test
    func secureConnection_whenShutdownTimeout_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)
        let timeout = NIOCore.TimeAmount.seconds(50)

        // When
        secureConnection.shutdownTimeout = timeout

        let sut = try secureConnection.build()

        // Then
        #expect(sut.shutdownTimeout == timeout)
    }

    @Test
    func secureConnection_whenPSKHint_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)
        let pskHint = "example.com"

        // When
        secureConnection.pskHint = pskHint

        let sut = try secureConnection.build()

        // Then
        #expect(sut.pskHint == pskHint)
    }

    @Test
    func secureConnection_whenApplicationProtocols_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)
        let applicationProtocolos = ["h2"]

        // When
        secureConnection.applicationProtocols = applicationProtocolos

        let sut = try secureConnection.build()

        // Then
        #expect(sut.applicationProtocols == applicationProtocolos)
    }

    @Test
    func secureConnection_whenTLSVersion_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)

        let minimumVersion = TLSVersion.tlsv11
        let maximumVersion = TLSVersion.tlsv13

        // When
        secureConnection.minimumTLSVersion = minimumVersion
        secureConnection.maximumTLSVersion = maximumVersion

        let sut = try secureConnection.build()

        // Then
        #expect(sut.minimumTLSVersion == minimumVersion)
        #expect(sut.maximumTLSVersion == maximumVersion)
    }

    @Test
    func secureConnection_whenCipherSuites_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)

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
        #expect(sut.cipherSuites == cipherSuites)
        #expect(sut.cipherSuiteValues == cipherSuitesValues)
    }

    @Test
    func secureConnection_whenClient_shouldBeValid() async throws {
        // Given
        var secureConnection = try #require(secureConnection)
        let configuration: TLSConfiguration = .clientDefault

        // When
        let sut = try secureConnection.build()

        // Then
        #expect(sut.certificateChain == configuration.certificateChain)
        #expect(sut.certificateVerification == configuration.certificateVerification)
        #expect(sut.trustRoots == configuration.trustRoots)
        #expect(sut.additionalTrustRoots == configuration.additionalTrustRoots)
        #expect(sut.privateKey == configuration.privateKey)
        #expect(sut.signingSignatureAlgorithms == configuration.signingSignatureAlgorithms)
        #expect(sut.verifySignatureAlgorithms == configuration.verifySignatureAlgorithms)
        #expect(sut.sendCANameList == configuration.sendCANameList)
        #expect(sut.renegotiationSupport == configuration.renegotiationSupport)
        #expect(sut.shutdownTimeout == configuration.shutdownTimeout)
        #expect(sut.pskHint == configuration.pskHint)
        #expect(sut.applicationProtocols == configuration.applicationProtocols)
        #expect(sut.keyLogCallback == nil)
        #expect(sut.pskClientCallback == nil)
        #expect(sut.pskServerCallback == nil)
        #expect(sut.minimumTLSVersion == configuration.minimumTLSVersion)
        #expect(sut.maximumTLSVersion == configuration.maximumTLSVersion)
        #expect(sut.cipherSuites == configuration.cipherSuites)
        #expect(sut.cipherSuiteValues == configuration.cipherSuiteValues)
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
        var secureConnection = try #require(secureConnection)
        let data = Data("Hello World".utf8)

        // When
        secureConnection.keyLogger = KeyLogger {
            #expect($0, data)
        }

        let sut = try secureConnection.build()

        // Then
        sut.keyLogCallback?(.init(data: data))
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
        var secureConnection = try #require(secureConnection)
        let identity = "apple.com"
        let resolver = ClientResolver()

        // When
        secureConnection.pskIdentityResolver = resolver

        let sut = try secureConnection.build()
        let result = try sut.pskClientProvider.map { try $0(.init(hint: identity, maxPSKLength: 1_000)) }

        // Then

        #expect(
            result?.identity,
            identity
        )

        #expect(
            result.map { Data($0.key) },
            Data(identity.utf8)
        )
    }
}
