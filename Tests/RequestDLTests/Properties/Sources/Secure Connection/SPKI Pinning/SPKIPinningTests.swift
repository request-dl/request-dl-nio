//
// See LICENSE for this package's licensing information.
//

import Crypto
import Logging
import RequestDLInternals
import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(NIOCore)
import NIOSSL
#else
import SwiftASN1
import X509
#endif

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

    /// `SPKIHash._makeProperty` must no-op the same way `Certificate`'s own guard does when
    /// declared outside its allowed context, instead of always succeeding and returning a leaf
    /// node regardless of context. `SPKIPinning` only ever finds its pins by searching its own
    /// `content` subtree for `SPKIHashNode`s (`outputs.node.search(for: SPKIHashNode.self)`), not
    /// through `SPKIHash`'s own `_makeProperty`, so a loose `SPKIHash` declared anywhere else
    /// (even directly inside `SecureConnection`, with no enclosing `SPKIPinning` at all) would
    /// silently contribute nothing, with no diagnostic.
    /// An undecodable pin can never match. Only `.urlSession` used to say so; the NIO executors
    /// treated it as "no match", so a mistyped backup pin looked fine until the certificate
    /// rotated. It's rejected at resolve time now, whatever the executor.
    @Test
    func pinning_whenAPinIsNotValidBase64_throws() async throws {
        await #expect(throws: Internals.SPKIHashError.self) {
            _ = try await resolve(
                TestProperty {
                    SecureConnection {
                        SPKIPinning {
                            SPKIHash("not base64!")
                        }
                    }
                }
            )
        }
    }

    @Test
    func pinning_whenAPinHasTheWrongDigestLength_throws() async throws {
        await #expect(throws: Internals.SPKIHashError.self) {
            _ = try await resolve(
                TestProperty {
                    SecureConnection {
                        SPKIPinning {
                            // A SHA-256 digest (32 bytes) declared as SHA-384 (48 bytes).
                            SPKIHash(Data(repeating: 0x1, count: 32).base64EncodedString(), algorithm: SHA384.self)
                        }
                    }
                }
            )
        }
    }

    /// An empty pin set is "nothing to pin" to every executor, so `.strict` over zero pins used to
    /// resolve fine and quietly validate the chain alone. It's rejected at resolve time instead.
    @Test
    func pinning_whenStrictAndEmptyPropertyForEach_throws() async throws {
        await #expect(throws: Internals.SPKIPinningError.self) {
            _ = try await resolve(
                TestProperty {
                    SecureConnection {
                        SPKIPinning(policy: .strict) {
                            PropertyForEach([String](), id: \.self) {
                                SPKIHash($0)
                            }
                        }
                    }
                }
            )
        }
    }

    @Test
    func pinning_whenAuditAndEmptyPropertyForEach_throws() async throws {
        await #expect(throws: Internals.SPKIPinningError.self) {
            _ = try await resolve(
                TestProperty {
                    SecureConnection {
                        SPKIPinning(policy: .audit) {
                            PropertyForEach([String](), id: \.self) {
                                SPKIHash($0)
                            }
                        }
                    }
                }
            )
        }
    }

    @Test
    func pinning_whenEveryPinIsBehindAFalseCondition_throws() async throws {
        let isEnabled = false

        await #expect(throws: Internals.SPKIPinningError.self) {
            _ = try await resolve(
                TestProperty {
                    SPKIPinning {
                        if isEnabled {
                            SPKIHash(Data(repeating: 0x1, count: 32))
                        }
                    }
                }
            )
        }
    }

    @Test
    func pinning_whenTheDeclarationHasNoSPKIHashAtAll_throws() async throws {
        await #expect(throws: Internals.SPKIPinningError.self) {
            _ = try await resolve(
                TestProperty {
                    SPKIPinning {
                        EmptyProperty()
                    }
                }
            )
        }
    }

    @Test
    func pinning_whenAtLeastOnePinSurvivesAFalseCondition_isStillAccepted() async throws {
        // Given
        let isEnabled = false
        let pin = Data(repeating: 0x1, count: 32)

        // When
        let resolved = try await resolve(
            TestProperty {
                SPKIPinning {
                    if isEnabled {
                        SPKIHash(Data(repeating: 0x2, count: 32))
                    }

                    SPKIHash(pin)
                }
            }
        )

        // Then
        #expect(
            resolved.session.configuration.secureConnection?.tlsPins
                == [.init(source: .rawData(pin), algorithm: SHA256.self)]
        )
    }

    /// `.verification(.none)` skips trust evaluation altogether, and with it the pin check under
    /// NIOSSL and URLSession, while Network.framework still runs it. The combination isn't
    /// rejected (`.none` is an explicit opt-out), but it is reported, whatever order the two are
    /// declared in.
    @Test
    func pinning_whenCombinedWithVerificationNone_logsAWarning() async throws {
        let pin = Data(repeating: 0x1, count: 32)

        let pinsInsideSecureConnection = try await warnings {
            TestProperty {
                SecureConnection {
                    SPKIPinning {
                        SPKIHash(pin)
                    }
                }
                .verification(.none)
            }
        }

        let verificationDeclaredBeforePinning = try await warnings {
            TestProperty {
                SecureConnection {}
                    .verification(.none)

                SPKIPinning {
                    SPKIHash(pin)
                }
            }
        }

        #expect(pinsInsideSecureConnection.count == 1)
        #expect(verificationDeclaredBeforePinning.count == 1)
    }

    @Test
    func pinning_whenVerificationIsNotNone_doesNotLog() async throws {
        let pin = Data(repeating: 0x1, count: 32)

        let fullVerification = try await warnings {
            TestProperty {
                SecureConnection {
                    SPKIPinning {
                        SPKIHash(pin)
                    }
                }
                .verification(.fullVerification)
            }
        }

        let verificationNoneWithoutPins = try await warnings {
            TestProperty {
                SecureConnection {}
                    .verification(.none)
            }
        }

        #expect(fullVerification.isEmpty)
        #expect(verificationNoneWithoutPins.isEmpty)
    }

    @Test
    func hash_whenDeclaredOutsideSPKIPinning_hasNoEffect() async throws {
        // Given
        let pin = Data(repeating: 0, count: 32)

        // When
        let resolved = try await resolve(
            TestProperty {
                SecureConnection {
                    SPKIHash(pin)
                }
            }
        )

        // Then
        #expect(resolved.session.configuration.secureConnection?.tlsPins == nil)
    }
}

extension SPKIPinningTests {

    fileprivate final class RecordBox: @unchecked Sendable {
        private let lock = SwiftAsyncStream.Lock()
        private var _records: [TestLogHandler.LogRecord] = []

        var records: [TestLogHandler.LogRecord] {
            lock.withLock { _records }
        }

        func append(_ record: TestLogHandler.LogRecord) {
            lock.withLock { _records.append(record) }
        }
    }

    /// The `.warning` records logged while resolving `property`.
    func warnings<Content: Property>(
        @PropertyBuilder content: () -> Content
    ) async throws -> [TestLogHandler.LogRecord] {
        let recordBox = RecordBox()
        let property = content()

        try await Logger.withTesting(
            level: .trace,
            recorded: { recordBox.append($0) },
            perform: { logger in
                var environment = RequestEnvironmentValues()
                environment.logger = logger

                _ = try await Resolve(root: property, environment: environment).build()
            }
        )

        return recordBox.records.filter { $0.level == .warning }
    }

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
