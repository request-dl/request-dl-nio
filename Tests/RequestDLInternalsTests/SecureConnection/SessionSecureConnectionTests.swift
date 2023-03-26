/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOSSL
@testable import RequestDLInternals

class SessionSecureConnectionTests: XCTestCase {

    var secureConnection: Session.SecureConnection!

    override func setUp() async throws {
        try await super.setUp()
        secureConnection = .init(.client)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        secureConnection = nil
    }

    /*
     XCTAssertEqual(sut.pskClientCallback, secureConnection.pskClientCallback)
     XCTAssertEqual(sut.pskServerCallback, secureConnection.pskServerCallback)
     XCTAssertEqual(sut.keyLogCallback, secureConnection.keyLogCallback)
     XCTAssertEqual(sut.certificateChain, secureConnection.certificateChain)
     XCTAssertEqual(sut.trustRoots, secureConnection.trustRoots)
     XCTAssertEqual(sut.additionalTrustRoots, secureConnection.additionalTrustRoots)
     XCTAssertEqual(sut.privateKey, secureConnection.privateKey)
     */

    func testSecureConnection_whenCertificateVerification_shouldBeValid() async throws {
        // Given
        let certificateVerification: CertificateVerification = .noHostnameVerification

        // When
        secureConnection.certificateVerification = certificateVerification

        let sut = try secureConnection.build()

        // Then
        XCTAssertEqual(sut.certificateVerification, certificateVerification)
    }

    func testSecureConnection_whenSigningSignatureAlgorithms_shouldBeValid() async throws {
        // Given
        let signatureAlgorithms: [SignatureAlgorithm] = [
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
        let signatureAlgorithms: [SignatureAlgorithm] = [
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
        let timeout = TimeAmount.seconds(50)

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
        let certificateChain = ChainCertificate([.file(certificates.certificateURL.path)])
        let privateKey = PrivateKeySource.file(certificates.privateKeyURL.path)

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
