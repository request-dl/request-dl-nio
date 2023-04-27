/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
import NIOCore
@testable import RequestDL

class InternalsSecureConnectionTests: XCTestCase {

    var secureConnection: Internals.SecureConnection!

    override func setUp() async throws {
        try await super.setUp()
        secureConnection = .init(.client)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        secureConnection = nil
    }

    func testSecureConnection_whenKeyLog_shouldBeValid() async throws {
        // Given
        let data = Data("Hello World".utf8)

        // When
        secureConnection.keyLogCallback = { @Sendable in
            var bytes = $0
            let receivedData = bytes.readData(length: bytes.readableBytes)
            precondition(data == receivedData)
        }

        let sut = try secureConnection.build()

        // Then
        sut.keyLogCallback?(.init(data: data))
    }

    func testSecureConnection_whenTrustRoots_shouldBeValid() async throws {
        // Given
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
        let server = Certificates().server()
        let certificatePath = server.certificateURL.absolutePath(percentEncoded: false)

        // When
        secureConnection.additionalTrustRoots = [.file(certificatePath)]

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.additionalTrustRoots, [.file(certificatePath)])
    }

    func testSecureConnection_whenPrivateKey_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let privateKeyPath = server.privateKeyURL.absolutePath(percentEncoded: false)

        // When
        secureConnection.privateKey = .file(privateKeyPath)

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.privateKey, .file(privateKeyPath))
    }

    func testSecureConnection_whenCertificateVerification_shouldBeValid() async throws {
        // Given
        let certificateVerification: NIOSSL.CertificateVerification = .noHostnameVerification

        // When
        secureConnection.certificateVerification = certificateVerification

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.certificateVerification, certificateVerification)
    }

    func testSecureConnection_whenSigningSignatureAlgorithms_shouldBeValid() async throws {
        // Given
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
        let sendCANameList = true

        // When
        secureConnection.sendCANameList = sendCANameList

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.sendCANameList, sendCANameList)
    }

    func testSecureConnection_whenRenegotiationSupport_shouldBeValid() async throws {
        // Given
        let renegotiationSupport: NIORenegotiationSupport = .once

        // When
        secureConnection.renegotiationSupport = renegotiationSupport

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.renegotiationSupport, renegotiationSupport)
    }

    func testSecureConnection_whenShutdownTimeout_shouldBeValid() async throws {
        // Given
        let timeout = NIOCore.TimeAmount.seconds(50)

        // When
        secureConnection.shutdownTimeout = timeout

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.shutdownTimeout, timeout)
    }

    func testSecureConnection_whenPSKHint_shouldBeValid() async throws {
        // Given
        let pskHint = "example.com"

        // When
        secureConnection.pskHint = pskHint

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.pskHint, pskHint)
    }

    func testSecureConnection_whenApplicationProtocols_shouldBeValid() async throws {
        // Given
        let applicationProtocolos = ["h2"]

        // When
        secureConnection.applicationProtocols = applicationProtocolos

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.applicationProtocols, applicationProtocolos)
    }

    func testSecureConnection_whenTLSVersion_shouldBeValid() async throws {
        // Given
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
        XCTAssertEqual(sut.cipherSuites, cipherSuites)
        XCTAssertEqual(sut.cipherSuiteValues, cipherSuitesValues)
    }

    func testSecureConnection_whenServer_shouldBeValid() async throws {
        // Given
        let certificates = Certificates().client()

        let certificateChain = Internals.CertificateChain.certificates([
            Internals.Certificate(
                certificates.certificateURL.absolutePath(percentEncoded: false),
                format: .pem
        )])

        let privateKey = Internals.PrivateKeySource.file(
            certificates.privateKeyURL.absolutePath(percentEncoded: false)
        )

        let configuration: TLSConfiguration = .makeServerConfiguration(
            certificateChain: try certificateChain.build(),
            privateKey: try privateKey.build()
        )

        // When
        secureConnection.context = .server
        secureConnection.certificateChain = certificateChain
        secureConnection.privateKey = privateKey

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

    func testSecureConnection_whenClient_shouldBeValid() async throws {
        // Given
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
}

extension InternalsSecureConnectionTests {

    private final class ClientResolver: SSLPSKClientIdentityResolver {

        func callAsFunction(_ hint: String) throws -> PSKClientIdentityResponse {
            .init(
                key: .init(Data(hint.utf8)),
                identity: hint
            )
        }
    }

    func testSecureConnection_whenPSKClient_shouldBeValid() async throws {
        // Given
        let identity = "apple.com"
        let resolver = ClientResolver()

        // When
        secureConnection.pskClientIdentityResolver = resolver

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

extension InternalsSecureConnectionTests {

    private final class ServerResolver: SSLPSKServerIdentityResolver {

        func callAsFunction(
            _ hint: String,
            client identity: String
        ) throws -> PSKServerIdentityResponse {
            .init(key: .init(Data([hint, identity].joined(separator: ",").utf8)))
        }
    }

    func testSecureConnection_whenPSKServer_shouldBeValid() async throws {
        // Given
        let hint = "default"
        let identity = "apple.com"
        let resolver = ServerResolver()

        // When
        secureConnection.pskServerIdentityResolver = resolver

        let sut = try secureConnection.build()
        let result = try sut.pskServerCallback.map { try Data($0(hint, identity).key) }

        // Then
        XCTAssertEqual(
            result,
            Data([hint, identity].joined(separator: ",").utf8)
        )
    }
}
