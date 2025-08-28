/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOCore
import NIOSSL
@testable import RequestDL

class SecureConnectionTests: XCTestCase {

    func testSecure_whenDefaultInit_shouldBeValid() async throws {
        // Given
        let secureConnection = Internals.SecureConnection()

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.certificateVerification, secureConnection.certificateVerification)
        XCTAssertEqual(sut?.signingSignatureAlgorithms, secureConnection.signingSignatureAlgorithms)
        XCTAssertEqual(sut?.verifySignatureAlgorithms, secureConnection.verifySignatureAlgorithms)
        XCTAssertEqual(sut?.sendCANameList, secureConnection.sendCANameList)
        XCTAssertEqual(sut?.renegotiationSupport, secureConnection.renegotiationSupport)
        XCTAssertEqual(sut?.shutdownTimeout, secureConnection.shutdownTimeout)
        XCTAssertEqual(sut?.applicationProtocols, secureConnection.applicationProtocols)
        XCTAssertEqual(sut?.minimumTLSVersion, secureConnection.minimumTLSVersion)
        XCTAssertEqual(sut?.maximumTLSVersion, secureConnection.maximumTLSVersion)
        #if !canImport(Network)
        XCTAssertEqual(sut?.cipherSuites, secureConnection.cipherSuites)
        #endif
        XCTAssertEqual(sut?.cipherSuiteValues, secureConnection.cipherSuiteValues)
        #if !canImport(Network)
        XCTAssertNil(sut?.keyLogger)
        #endif
    }

    func testSecure_whenUpdatesVerification_shouldBeValid() async throws {
        // Given
        let verification: RequestDL.CertificateVerification = .noHostnameVerification

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .verification(verification)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.certificateVerification, verification.build())
    }

    func testSecure_whenUpdatesSigningSignatureAlgorithms_shouldBeValid() async throws {
        // Given
        let algorithm1 = RequestDL.SignatureAlgorithm.rsaPkcs1Sha1
        let algorithm2 = RequestDL.SignatureAlgorithm.rsaPssRsaeSha512

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .signingSignatureAlgorithms(algorithm1, algorithm2)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.signingSignatureAlgorithms, [algorithm1, algorithm2].map {
            $0.build()
        })
    }

    func testSecure_whenUpdatesVerifySignatureAlgorithms_shouldBeValid() async throws {
        // Given
        let algorithm1 = RequestDL.SignatureAlgorithm.ecdsaSecp256R1Sha256
        let algorithm2 = RequestDL.SignatureAlgorithm.ecdsaSecp521R1Sha512

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .verifySignatureAlgorithms(algorithm1, algorithm2)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.verifySignatureAlgorithms, [algorithm1, algorithm2].map {
            $0.build()
        })
    }

    func testSecure_whenUpdatesSendCANameList_shouldBeValid() async throws {
        // Given
        let isDisabled = true

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .sendCANameListDisabled(isDisabled)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.sendCANameList, !isDisabled)
    }

    func testSecure_whenUpdatesRenegotiationSupport_shouldBeValid() async throws {
        // Given
        let renegotiationSupport: NIORenegotiationSupport = .always

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .renegotiationSupport(.always)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.renegotiationSupport, renegotiationSupport)
    }

    func testSecure_whenUpdatesShutdownTimeout_shouldBeValid() async throws {
        // Given
        let timeout = UnitTime.seconds(60)

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .shutdownTimeout(timeout)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.shutdownTimeout, timeout.build())
    }

    func testSecure_whenUpdatesApplicationProtocols_shouldBeValid() async throws {
        // Given
        let protocol1 = "http"
        let protocol2 = "https"

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .applicationProtocols(protocol1, protocol2)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.applicationProtocols, [protocol1, protocol2])
    }

    func testSecure_whenSetClosedRangeOfTLSVersions_shouldBeValid() async throws {
        // Given
        let minVersion: RequestDL.TLSVersion = .v1_1
        let maxVersion: RequestDL.TLSVersion = .v1_3

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .version(minVersion ... maxVersion)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.minimumTLSVersion, minVersion.build())
        XCTAssertEqual(sut?.maximumTLSVersion, maxVersion.build())
    }

    func testSecure_whenSetRangeOfTLSVersions_shouldBeValid() async throws {
        // Given
        let minVersion: RequestDL.TLSVersion = .v1_1
        let maxVersion: RequestDL.TLSVersion = .v1_3

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .version(minVersion ..< maxVersion)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.minimumTLSVersion, minVersion.build())
        XCTAssertEqual(sut?.maximumTLSVersion, maxVersion.downgrade.build())
    }

    func testSecure_whenSetMaxTLSVersion_shouldBeValid() async throws {
        // Given
        let maxVersion: RequestDL.TLSVersion = .v1_1

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .version(maximum: maxVersion)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.maximumTLSVersion, maxVersion.build())
    }

    func testSecure_whenSetMinTLSVersion_shouldBeValid() async throws {
        // Given
        let minVersion: RequestDL.TLSVersion = .v1_3

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .version(minimum: minVersion)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.minimumTLSVersion, minVersion.build())
    }

    func testSecure_whenUpdatesTLSVersions_shouldBeValid() async throws {
        // Given
        let minVersion: RequestDL.TLSVersion = .v1
        let maxVersion: RequestDL.TLSVersion = .v1_2

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .version(minimum: minVersion, maximum: maxVersion)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.minimumTLSVersion, minVersion.build())
        XCTAssertEqual(sut?.maximumTLSVersion, maxVersion.build())
    }

    #if !canImport(Network)
    func testSecure_whenUpdatesCipherSuites_shouldBeValid() async throws {
        // Given
        let suite1 = "TLS_AES_128_GCM_SHA256"
        let suite2 = "TLS_CHACHA20_POLY1305_SHA256"

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .cipherSuites(suite1, suite2)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.cipherSuites, [suite1, suite2].joined(separator: ":"))
    }
    #endif

    func testSecure_whenUpdatesCipherSuiteValues_shouldBeValid() async throws {
        // Given
        let suite1: RequestDL.TLSCipher = .TLS_AES_128_GCM_SHA256
        let suite2: RequestDL.TLSCipher = .TLS_CHACHA20_POLY1305_SHA256

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .cipherSuites(suite1, suite2)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertEqual(sut?.cipherSuiteValues, [suite1, suite2].map {
            $0.build()
        })
    }

    #if !canImport(Network)
    func testSecure_whenUpdatesKeyLogger() async throws {
        // Given
        final class KeyLogger: SSLKeyLogger {
            func callAsFunction(_ bytes: NIOCore.ByteBuffer) {}
        }

        let logger = KeyLogger()

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .keyLogger(logger)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        XCTAssertTrue(sut?.keyLogger === logger)
    }
    #endif

    func testSecure_whenAccessBody_shouldBeNever() async throws {
        // When
        let sut = SecureConnection {}

        // Then
        try await assertNever(sut.body)
    }
}
