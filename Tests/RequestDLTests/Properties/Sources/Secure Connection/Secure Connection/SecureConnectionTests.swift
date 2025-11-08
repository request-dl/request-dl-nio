/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOCore
import NIOSSL
@testable import RequestDL

struct SecureConnectionTests {

    @Test
    func secure_whenDefaultInit_shouldBeValid() async throws {
        // Given
        let secureConnection = Internals.SecureConnection()

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
        })

        let sut = try #require(resolved.session.configuration.secureConnection)

        // Then
        #expect(sut.isCompatibleWithNetworkFramework)
        #expect(sut.certificateVerification == secureConnection.certificateVerification)
        #expect(sut.signingSignatureAlgorithms == secureConnection.signingSignatureAlgorithms)
        #expect(sut.verifySignatureAlgorithms == secureConnection.verifySignatureAlgorithms)
        #expect(sut.sendCANameList == secureConnection.sendCANameList)
        #expect(sut.renegotiationSupport == secureConnection.renegotiationSupport)
        #expect(sut.shutdownTimeout == secureConnection.shutdownTimeout)
        #expect(sut.applicationProtocols == secureConnection.applicationProtocols)
        #expect(sut.minimumTLSVersion == secureConnection.minimumTLSVersion)
        #expect(sut.maximumTLSVersion == secureConnection.maximumTLSVersion)
        #expect(sut.cipherSuites == secureConnection.cipherSuites)
        #expect(sut.cipherSuiteValues == secureConnection.cipherSuiteValues)
        #expect(sut.keyLogger == nil)
    }

    @Test
    func secure_whenUpdatesVerification_shouldBeValid() async throws {
        // Given
        let verification: RequestDL.CertificateVerification = .noHostnameVerification

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .verification(verification)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        #expect(sut?.certificateVerification == verification.build())
    }

    @Test
    func secure_whenUpdatesSigningSignatureAlgorithms_shouldBeValid() async throws {
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
        #expect(sut?.signingSignatureAlgorithms == [algorithm1, algorithm2].map {
            $0.build()
        })
    }

    @Test
    func secure_whenUpdatesVerifySignatureAlgorithms_shouldBeValid() async throws {
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
        #expect(sut?.verifySignatureAlgorithms == [algorithm1, algorithm2].map {
            $0.build()
        })
    }

    @Test
    func secure_whenUpdatesSendCANameList_shouldBeValid() async throws {
        // Given
        let isDisabled = true

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .sendCANameListDisabled(isDisabled)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        #expect(sut?.sendCANameList == !isDisabled)
    }

    @Test
    func secure_whenUpdatesRenegotiationSupport_shouldBeValid() async throws {
        // Given
        let renegotiationSupport: NIORenegotiationSupport = .always

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .renegotiationSupport(.always)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        #expect(sut?.renegotiationSupport == renegotiationSupport)
    }

    @Test
    func secure_whenUpdatesShutdownTimeout_shouldBeValid() async throws {
        // Given
        let timeout = UnitTime.seconds(60)

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .shutdownTimeout(timeout)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        #expect(sut?.shutdownTimeout == timeout.build())
    }

    @Test
    func secure_whenUpdatesApplicationProtocols_shouldBeValid() async throws {
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
        #expect(sut?.applicationProtocols == [protocol1, protocol2])
    }

    @Test
    func secure_whenSetClosedRangeOfTLSVersions_shouldBeValid() async throws {
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
        #expect(sut?.minimumTLSVersion == minVersion.build())
        #expect(sut?.maximumTLSVersion == maxVersion.build())
    }

    @Test
    func secure_whenSetRangeOfTLSVersions_shouldBeValid() async throws {
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
        #expect(sut?.minimumTLSVersion == minVersion.build())
        #expect(sut?.maximumTLSVersion == maxVersion.downgrade.build())
    }

    @Test
    func secure_whenSetMaxTLSVersion_shouldBeValid() async throws {
        // Given
        let maxVersion: RequestDL.TLSVersion = .v1_1

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .version(maximum: maxVersion)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        #expect(sut?.maximumTLSVersion == maxVersion.build())
    }

    @Test
    func secure_whenSetMinTLSVersion_shouldBeValid() async throws {
        // Given
        let minVersion: RequestDL.TLSVersion = .v1_3

        // When
        let resolved = try await resolve(TestProperty {
            RequestDL.SecureConnection {}
                .version(minimum: minVersion)
        })

        let sut = resolved.session.configuration.secureConnection

        // Then
        #expect(sut?.minimumTLSVersion == minVersion.build())
    }

    @Test
    func secure_whenUpdatesTLSVersions_shouldBeValid() async throws {
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
        #expect(sut?.minimumTLSVersion == minVersion.build())
        #expect(sut?.maximumTLSVersion == maxVersion.build())
    }

    @Test
    func secure_whenUpdatesCipherSuites_shouldBeValid() async throws {
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
        #expect(sut?.cipherSuites == [suite1, suite2].joined(separator: ":"))
    }

    @Test
    func secure_whenUpdatesCipherSuiteValues_shouldBeValid() async throws {
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
        #expect(sut?.cipherSuiteValues == [suite1, suite2].map {
            $0.build()
        })
    }

    @Test
    func secure_whenUpdatesKeyLogger() async throws {
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
        #expect(sut?.keyLogger === logger)
    }

    @Test
    func secure_whenAccessBody_shouldBeNever() async throws {
        // When
        let sut = SecureConnection {}

        // Then
        try await assertNever(sut.body)
    }
}
