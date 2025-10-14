/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
import NIOCore
@testable import RequestDL

class InternalsSecureConnectionTests: XCTestCase {

    var secureConnection: Internals.SecureConnection?

    override func setUp() async throws {
        try await super.setUp()
        secureConnection = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        secureConnection = nil
    }

    func testSecureConnection_whenDefaultTrustNotSet_shouldBeFalse() async throws {
        // Given
        let secureConnection = try XCTUnwrap(secureConnection)
        // Then
        XCTAssertFalse(secureConnection.useDefaultTrustRoots)
    }

    func testSecureConnection_whenSetDefaultTrust() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)

        // When
        secureConnection.useDefaultTrustRoots = true

        // Then
        XCTAssertTrue(secureConnection.useDefaultTrustRoots)
    }

    func testSecureConnection_whenTrustRoots_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)

        let server = Certificates().server()
        let certificatePath = server.certificateURL.absolutePath(percentEncoded: false)

        // When
        secureConnection.trustRoots = .file(certificatePath)

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.trustRoots, .file(certificatePath))
    }

    func testSecureConnection_whenAdditionalTrustRoots_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)

        let server = Certificates().server()
        let certificatePath = server.certificateURL.absolutePath(percentEncoded: false)

        // When
        secureConnection.additionalTrustRoots = [.file(certificatePath)]

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.additionalTrustRoots, [.file(certificatePath)])
    }

    #if !canImport(Network)
    func testSecureConnection_whenPrivateKey_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)

        let server = Certificates().server()
        let privateKeyPath = server.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        secureConnection.privateKey = .file(privateKeyPath)

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.privateKey, .file(privateKeyPath))
    }
    #endif

    func testSecureConnection_whenCertificateVerification_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)
        let certificateVerification: NIOSSL.CertificateVerification = .noHostnameVerification

        // When
        secureConnection.certificateVerification = certificateVerification

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.certificateVerification, certificateVerification)
    }

    func testSecureConnection_whenSigningSignatureAlgorithms_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)
        
        let signatureAlgorithms: [NIOSSL.SignatureAlgorithm] = [
            .ecdsaSecp256R1Sha256,
            .ecdsaSecp384R1Sha384
        ]

        // When
        secureConnection.signingSignatureAlgorithms = signatureAlgorithms

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.signingSignatureAlgorithms, signatureAlgorithms)
    }

    func testSecureConnection_whenVerifySignatureAlgorithms_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)

        let signatureAlgorithms: [NIOSSL.SignatureAlgorithm] = [
            .ecdsaSecp256R1Sha256,
            .ecdsaSecp384R1Sha384
        ]

        // When
        secureConnection.verifySignatureAlgorithms = signatureAlgorithms

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.verifySignatureAlgorithms, signatureAlgorithms)
    }

    func testSecureConnection_whenSendCANameList_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)
        let sendCANameList = true

        // When
        secureConnection.sendCANameList = sendCANameList

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.sendCANameList, sendCANameList)
    }

    func testSecureConnection_whenRenegotiationSupport_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)
        let renegotiationSupport: NIORenegotiationSupport = .once

        // When
        secureConnection.renegotiationSupport = renegotiationSupport

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.renegotiationSupport, renegotiationSupport)
    }

    func testSecureConnection_whenShutdownTimeout_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)
        let timeout = NIOCore.TimeAmount.seconds(50)

        // When
        secureConnection.shutdownTimeout = timeout

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.shutdownTimeout, timeout)
    }

    func testSecureConnection_whenPSKHint_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)
        let pskHint = "example.com"

        // When
        secureConnection.pskHint = pskHint

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.pskHint, pskHint)
    }

    func testSecureConnection_whenApplicationProtocols_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)
        let applicationProtocolos = ["h2"]

        // When
        secureConnection.applicationProtocols = applicationProtocolos

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.applicationProtocols, applicationProtocolos)
    }

    func testSecureConnection_whenTLSVersion_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)

        let minimumVersion = TLSVersion.tlsv11
        let maximumVersion = TLSVersion.tlsv13

        // When
        secureConnection.minimumTLSVersion = minimumVersion
        secureConnection.maximumTLSVersion = maximumVersion

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.minimumTLSVersion, minimumVersion)
        XCTAssertEqual(sut.maximumTLSVersion, maximumVersion)
    }

    func testSecureConnection_whenCipherSuites_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)

        let cipherSuitesValues: [NIOTLSCipher] = [
            .TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA,
            .TLS_RSA_WITH_AES_256_GCM_SHA384
        ]

        let cipherSuites = [
            "TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA",
            "TLS_RSA_WITH_AES_256_GCM_SHA384"
        ].joined(separator: ":")

        // When
        #if !canImport(Network)
        secureConnection.cipherSuites = cipherSuites
        #endif
        secureConnection.cipherSuiteValues = cipherSuitesValues

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.cipherSuites, cipherSuites)
        XCTAssertEqual(sut.cipherSuiteValues, cipherSuitesValues)
    }

    func testSecureConnection_whenClient_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)
        let configuration: TLSConfiguration = .clientDefault

        // When
        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.certificateChain, configuration.certificateChain)
        XCTAssertEqual(sut.certificateVerification, configuration.certificateVerification)
        XCTAssertEqual(sut.trustRoots, configuration.trustRoots)
        XCTAssertEqual(sut.additionalTrustRoots, configuration.additionalTrustRoots)
        XCTAssertEqual(sut.privateKey, configuration.privateKey)
        XCTAssertEqual(sut.signingSignatureAlgorithms, configuration.signingSignatureAlgorithms)
        XCTAssertEqual(sut.verifySignatureAlgorithms, configuration.verifySignatureAlgorithms)
        XCTAssertEqual(sut.sendCANameList, configuration.sendCANameList)
        XCTAssertEqual(sut.renegotiationSupport, configuration.renegotiationSupport)
        XCTAssertEqual(sut.shutdownTimeout, configuration.shutdownTimeout)
        XCTAssertEqual(sut.pskHint, configuration.pskHint)
        XCTAssertEqual(sut.applicationProtocols, configuration.applicationProtocols)
        XCTAssertNil(sut.keyLogCallback)
        XCTAssertNil(sut.pskClientCallback)
        XCTAssertNil(sut.pskServerCallback)
        XCTAssertEqual(sut.minimumTLSVersion, configuration.minimumTLSVersion)
        XCTAssertEqual(sut.maximumTLSVersion, configuration.maximumTLSVersion)
        XCTAssertEqual(sut.cipherSuites, configuration.cipherSuites)
        XCTAssertEqual(sut.cipherSuiteValues, configuration.cipherSuiteValues)
    }

    func testSecureConnection_whenEquals() async throws {
        // Given
        let lhs = Internals.SecureConnection()
        let rhs = Internals.SecureConnection()

        // Then
        XCTAssertEqual(lhs, rhs)
    }

    func testSecureConnection_whenNotEquals() async throws {
        // Given
        var lhs = Internals.SecureConnection()
        var rhs = Internals.SecureConnection()

        // When
        lhs.maximumTLSVersion = .tlsv12
        rhs.maximumTLSVersion = .tlsv13

        // Then
        XCTAssertNotEqual(lhs, rhs)
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

    #if !canImport(Network)
    func testSecureConnection_whenKeyLog_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)
        let data = Data("Hello World".utf8)

        // When
        secureConnection.keyLogger = KeyLogger {
            XCTAssertEqual($0, data)
        }

        let sut = try secureConnection.build()

        // Then
        sut.keyLogCallback?(.init(data: data))
    }
    #endif
}

extension InternalsSecureConnectionTests {

    private final class ClientResolver: SSLPSKIdentityResolver {

        func callAsFunction(_ hint: String) throws -> PSKClientIdentityResponse {
            .init(
                key: .init(Data(hint.utf8)),
                identity: hint
            )
        }
    }

    func testSecureConnection_whenPSKClient_shouldBeValid() async throws {
        // Given
        var secureConnection = try XCTUnwrap(secureConnection)
        let identity = "apple.com"
        let resolver = ClientResolver()

        // When
        secureConnection.pskIdentityResolver = resolver

        let sut = try secureConnection.build()
        let result = try sut.pskClientCallback.map { try $0(identity) }

        // Then

        XCTAssertEqual(
            result?.identity,
            identity
        )

        XCTAssertEqual(
            result.map { Data($0.key) },
            Data(identity.utf8)
        )
    }
}
