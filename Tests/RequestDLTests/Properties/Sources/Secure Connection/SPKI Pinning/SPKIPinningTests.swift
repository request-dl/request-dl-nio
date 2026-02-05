/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOSSL
import Crypto
@testable import RequestDL

struct SPKIPinningTests {

    @Test
    func pinning_whenCertificate_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let serverPin = try hashSPKI(from: server.certificateURL)
        let clientPin = try hashSPKI(from: client.certificateURL)

        // When
        let resolved = try await resolve(TestProperty {
            SecureConnection {
                SPKIPinning {
                    PropertyForEach(serverPin, id: \.self) {
                        SPKIHash($0)
                    }

                    PropertyForEach(clientPin, id: \.self) {
                        SPKIHash($0)
                    }
                }
            }
        })

        // Then
        let secureConnection = try #require(resolved.session.configuration.secureConnection)
        #expect(secureConnection.tlsPinningPolicy == .strict)
        #expect(secureConnection.tlsPins == (serverPin + clientPin).map {
            .init(source: .rawData($0), algorithm: SHA256.self)
        })
    }

    @Test
    func pinning_whenCertificateWithAuditPolicy_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let serverPin = try hashSPKI(from: server.certificateURL)
        let clientPin = try hashSPKI(from: client.certificateURL)

        // When
        let resolved = try await resolve(TestProperty {
            SecureConnection {
                SPKIPinning(policy: .audit) {
                    PropertyForEach(serverPin, id: \.self) {
                        SPKIHash($0)
                    }

                    PropertyForEach(clientPin, id: \.self) {
                        SPKIHash($0)
                    }
                }
            }
        })

        // Then
        let secureConnection = try #require(resolved.session.configuration.secureConnection)
        #expect(secureConnection.tlsPinningPolicy == .audit)
        #expect(secureConnection.tlsPins == (serverPin + clientPin).map {
            .init(source: .rawData($0), algorithm: SHA256.self)
        })
    }
}

extension SPKIPinningTests {

    func hashSPKI(from url: URL) throws -> [Data] {
        try NIOSSLCertificate.fromPEMFile(
            url.absolutePath(percentEncoded: false)
        )
        .map {
            let bytes = try $0.extractPublicKey().toSPKIBytes()
            return Data(SHA256.hash(data: Data(bytes)))
        }
    }
}
