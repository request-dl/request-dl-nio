//
// See LICENSE for this package's licensing information.
//

import Crypto
import RequestDLInternals
import Testing

#if canImport(NIOCore)
import NIOSSL
#else
import SwiftASN1
import X509
#endif

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

struct SPKIPinningTests {

    @Test
    func pinning_whenCertificate_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let serverPin = try hashSPKI(from: server.certificateURL)
        let clientPin = try hashSPKI(from: client.certificateURL)

        // When
        let resolved = try await resolve(
            TestProperty {
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
            }
        )

        // Then
        let secureConnection = try #require(resolved.session.configuration.secureConnection)
        #expect(secureConnection.tlsPinningPolicy == .strict)
        #expect(
            secureConnection.tlsPins
                == (serverPin + clientPin).map {
                    .init(source: .rawData($0), algorithm: SHA256.self)
                }
        )
    }

    @Test
    func pinning_whenCertificateWithAuditPolicy_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let serverPin = try hashSPKI(from: server.certificateURL)
        let clientPin = try hashSPKI(from: client.certificateURL)

        // When
        let resolved = try await resolve(
            TestProperty {
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
            }
        )

        // Then
        let secureConnection = try #require(resolved.session.configuration.secureConnection)
        #expect(secureConnection.tlsPinningPolicy == .audit)
        #expect(
            secureConnection.tlsPins
                == (serverPin + clientPin).map {
                    .init(source: .rawData($0), algorithm: SHA256.self)
                }
        )
    }
}

extension SPKIPinningTests {

    /// SPKI extraction mirrors `Internals.DarwinTrustEvaluation.chainSPKIDERBytes(of:)` exactly
    /// (NIOSSL when it's in the build, `X509`'s own portable ASN.1 parser otherwise), so this
    /// keeps agreeing with whatever `.urlSession`'s real handshake actually pins against under
    /// either build configuration.
    func hashSPKI(from url: URL) throws -> [Data] {
        try Internals.Certificate.resolvedPEMCertificateDERBytes(of: Data(contentsOf: url))
            .map { derBytes in
                #if canImport(NIOCore)
                let certificate = try NIOSSLCertificate(bytes: [UInt8](derBytes), format: .der)
                let bytes = try certificate.extractPublicKey().toSPKIBytes()
                #else
                let parsed = try X509.Certificate(derEncoded: [UInt8](derBytes))
                var serializer = DER.Serializer()
                try parsed.publicKey.serialize(into: &serializer)
                let bytes = serializer.serializedBytes
                #endif

                return Data(SHA256.hash(data: Data(bytes)))
            }
    }
}
