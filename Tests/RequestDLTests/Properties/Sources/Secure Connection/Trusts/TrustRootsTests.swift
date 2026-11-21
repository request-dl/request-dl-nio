//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

struct TrustRootsTests {

    @Test
    func trustRoots_whenCertificates_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let serverCertificate = try Array(Data(contentsOf: server.certificateURL))

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.TrustRoots {
                        RequestDL.Certificate(client.certificateURL.absolutePath(percentEncoded: false))
                        RequestDL.Certificate(serverCertificate)
                    }
                }
            }
        )

        // Then
        #expect(!(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true))
        #expect(
            resolved.session.configuration.secureConnection?.trustRoots
                == .certificates([
                    .init(client.certificateURL.absolutePath(percentEncoded: false), format: .pem),
                    .init(serverCertificate, format: .pem),
                ])
        )
    }

    @Test
    func trustRoots_whenFile_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let data = try [client, server]
            .map { try Data(contentsOf: $0.certificateURL) }
            .reduce(Data(), +)

        let fileURL =
            temporaryDirectoryURL
            .appendingPathComponent("RequestDL.\(UUID())")
            .appendingPathComponent("merged.pem")

        defer { fileURL.scheduleRemoval() }
        try await fileURL.createPathIfNeeded()

        try data.write(to: fileURL)

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.TrustRoots(fileURL.absolutePath(percentEncoded: false))
                }
            }
        )

        // Then
        #expect(!(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true))
        #expect(
            resolved.session.configuration.secureConnection?.trustRoots
                == .file(
                    fileURL.absolutePath(percentEncoded: false)
                )
        )
    }

    @Test
    func trustRoots_whenBytes_shouldBeValid() async throws {
        // Given
        let server = Certificates().server()
        let client = Certificates().client()

        let data = try [client, server]
            .map { try Data(contentsOf: $0.certificateURL) }
            .reduce(Data(), +)

        let bytes = Array(data)

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.TrustRoots(bytes)
                }
            }
        )

        // Then
        #expect(!(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true))
        #expect(
            resolved.session.configuration.secureConnection?.trustRoots == .bytes(bytes)
        )
    }

    @Test
    func trustRoots_whenUsedWithoutEnclosingSecureConnection_shouldStillBeValid() async throws {
        // Given
        // `TrustRoots` must work standalone, without an enclosing `SecureConnection`. The base
        // `Internals.SecureConnection` is created lazily the first time it's needed.
        let bytes: [UInt8] = [0, 1, 2]

        // When
        let resolved = try await resolve(
            TestProperty {
                RequestDL.TrustRoots {
                    RequestDL.Certificate(bytes)
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.trustRoots
                == .certificates([.init(bytes, format: .pem)])
        )
    }

    /// `TrustRoots` replaces the system roots. With no certificate left it used to resolve fine and
    /// leave the system store in use, the same fail-open an empty `SPKIPinning` had.
    @Test
    func trustRoots_whenEveryCertificateIsBehindAFalseCondition_throws() async throws {
        let isEnabled = false

        await #expect(throws: Internals.EmptyTrustRootsError.self) {
            _ = try await resolve(
                TestProperty {
                    RequestDL.SecureConnection {
                        RequestDL.TrustRoots {
                            if isEnabled {
                                RequestDL.Certificate([0, 1, 2])
                            }
                        }
                    }
                }
            )
        }
    }

    @Test
    func trustRoots_whenEmptyPropertyForEach_throws() async throws {
        await #expect(throws: Internals.EmptyTrustRootsError.self) {
            _ = try await resolve(
                TestProperty {
                    RequestDL.SecureConnection {
                        RequestDL.TrustRoots {
                            PropertyForEach([[UInt8]](), id: \.self) {
                                RequestDL.Certificate($0)
                            }
                        }
                    }
                }
            )
        }
    }

    @Test
    func trustRoots_whenUsedStandaloneWithoutCertificates_throws() async throws {
        await #expect(throws: Internals.EmptyTrustRootsError.self) {
            _ = try await resolve(
                TestProperty {
                    RequestDL.TrustRoots {
                        PropertyForEach([[UInt8]](), id: \.self) {
                            RequestDL.Certificate($0)
                        }
                    }
                }
            )
        }
    }

    @Test
    func trustRoots_whenAtLeastOneCertificateIsEnabled_shouldBeValid() async throws {
        let isEnabled = true

        let resolved = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    RequestDL.TrustRoots {
                        if isEnabled {
                            RequestDL.Certificate([0, 1, 2])
                        }
                    }
                }
            }
        )

        #expect(!(resolved.session.configuration.secureConnection?.useDefaultTrustRoots ?? true))
        #expect(
            resolved.session.configuration.secureConnection?.trustRoots
                == .certificates([.init([0, 1, 2], format: .pem)])
        )
    }

    @Test
    func trustRoots_whenAccessBody_shouldBeNever() async throws {
        // Given
        let sut = RequestDL.TrustRoots {
            RequestDL.Certificate([0, 1, 2])
        }

        // Then
        try await assertNever(sut.body)
    }
}
