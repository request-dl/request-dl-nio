//
// See LICENSE for this package's licensing information.
//

import Crypto
import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// A `SecureConnection` declared after other secure connection properties used to replace them
/// all, dropping an `SPKIPinning`, `TrustRoots`, `Certificates`/`PrivateKey`, `AdditionalTrustRoots`
/// or `DefaultTrustRoots` declared before it without a trace. It now builds on top of them
/// (`.merging`, the default), and `.override` is the explicit way to get the old reset.
struct SecureConnectionModeTests {

    private let pin = Data(repeating: 0x1, count: 32)

    private var certificatePath: String {
        Certificates().client().certificateURL.absolutePath(percentEncoded: false)
    }

    private var privateKeyPath: String {
        Certificates().client().privateKeyURL.absolutePath(percentEncoded: false)
    }

    // MARK: - Default (.merging)

    @Test
    func default_keepsPinsAndPolicyDeclaredBefore() async throws {
        let sut = try await resolve(
            TestProperty {
                SPKIPinning(policy: .audit) {
                    SPKIHash(pin)
                }

                RequestDL.SecureConnection {}
                    .version(minimum: .v1_2)
            }
        ).session.configuration.secureConnection

        #expect(sut?.tlsPins == [.init(source: .rawData(pin), algorithm: SHA256.self)])
        #expect(sut?.tlsPinningPolicy == .audit)
        #expect(sut?.minimumTLSVersion == TLSVersion.v1_2.build())
    }

    @Test
    func default_keepsTrustRootsDeclaredBefore() async throws {
        let sut = try await resolve(
            TestProperty {
                TrustRoots {
                    RequestDL.Certificate(certificatePath)
                }

                RequestDL.SecureConnection {}
                    .version(minimum: .v1_2)
            }
        ).session.configuration.secureConnection

        #expect(sut?.trustRoots == .certificates([.init(certificatePath, format: .pem)]))
        #expect(sut?.trustRootsAreExclusive == true)
    }

    @Test
    func default_keepsCertificatesAndPrivateKeyDeclaredBefore() async throws {
        let sut = try await resolve(
            TestProperty {
                Certificates {
                    RequestDL.Certificate(certificatePath)
                }

                PrivateKey(privateKeyPath, format: .pem)

                RequestDL.SecureConnection {}
                    .version(minimum: .v1_2)
            }
        ).session.configuration.secureConnection

        #expect(sut?.certificateChain == .certificates([.init(certificatePath, format: .pem)]))
        #expect(sut?.privateKey == .privateKey(.init(privateKeyPath, format: .pem)))
    }

    @Test
    func default_keepsAdditionalTrustRootsDeclaredBefore() async throws {
        let sut = try await resolve(
            TestProperty {
                AdditionalTrustRoots {
                    RequestDL.Certificate(certificatePath)
                }

                RequestDL.SecureConnection {}
                    .version(minimum: .v1_2)
            }
        ).session.configuration.secureConnection

        #expect(sut?.additionalTrustRoots == [.certificates([.init(certificatePath, format: .pem)])])
    }

    @Test
    func default_keepsDefaultTrustRootsDeclaredBefore() async throws {
        let sut = try await resolve(
            TestProperty {
                DefaultTrustRoots()

                RequestDL.SecureConnection {}
                    .version(minimum: .v1_2)
            }
        ).session.configuration.secureConnection

        #expect(sut?.useDefaultTrustRoots == true)
    }

    @Test
    func default_matchesAnExplicitMerging() async throws {
        let implicit = try await resolve(
            TestProperty {
                SPKIPinning {
                    SPKIHash(pin)
                }

                RequestDL.SecureConnection {}
                    .version(minimum: .v1_2)
            }
        ).session.configuration.secureConnection

        let withoutContent = try await resolve(
            TestProperty {
                SPKIPinning {
                    SPKIHash(pin)
                }

                RequestDL.SecureConnection()
                    .version(minimum: .v1_2)
            }
        ).session.configuration.secureConnection

        let explicit = try await resolve(
            TestProperty {
                SPKIPinning {
                    SPKIHash(pin)
                }

                RequestDL.SecureConnection(.merging)
                    .version(minimum: .v1_2)
            }
        ).session.configuration.secureConnection

        #expect(implicit == explicit)
        #expect(withoutContent == explicit)
    }

    /// With nothing declared before it, there's nothing to merge with, so both modes agree.
    @Test
    func default_whenNothingWasDeclaredBefore_matchesOverride() async throws {
        let merged = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {}
                    .version(minimum: .v1_2)
                    .verification(.noHostnameVerification)
            }
        ).session.configuration.secureConnection

        let overridden = try await resolve(
            TestProperty {
                RequestDL.SecureConnection(.override) {}
                    .version(minimum: .v1_2)
                    .verification(.noHostnameVerification)
            }
        ).session.configuration.secureConnection

        var expected = Internals.SecureConnection()
        expected.minimumTLSVersion = TLSVersion.v1_2.build()
        expected.certificateVerification = CertificateVerification.noHostnameVerification.build()

        #expect(merged == expected)
        #expect(overridden == expected)
    }

    /// What the wrapper configures wins over the same setting declared before, and what it
    /// doesn't mention stays.
    @Test
    func default_whenTheWrapperConfiguresAField_itWinsOverTheOneDeclaredBefore() async throws {
        let sut = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {}
                    .version(minimum: .v1_2)
                    .verification(.noHostnameVerification)

                RequestDL.SecureConnection {}
                    .version(minimum: .v1_3)
            }
        ).session.configuration.secureConnection

        #expect(sut?.minimumTLSVersion == TLSVersion.v1_3.build())
        #expect(sut?.certificateVerification == CertificateVerification.noHostnameVerification.build())
    }

    @Test
    func default_whenPinsAreDeclaredAfter_isUnaffected() async throws {
        let sut = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {}
                    .version(minimum: .v1_2)

                SPKIPinning {
                    SPKIHash(pin)
                }
            }
        ).session.configuration.secureConnection

        #expect(sut?.tlsPins?.count == 1)
        #expect(sut?.minimumTLSVersion == TLSVersion.v1_2.build())
    }

    @Test
    func default_whenPinsAreDeclaredInside_isStillAccepted() async throws {
        let sut = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    SPKIPinning {
                        SPKIHash(pin)
                    }
                }
                .version(minimum: .v1_2)
            }
        ).session.configuration.secureConnection

        #expect(sut?.tlsPins?.count == 1)
    }

    // MARK: - .override

    /// `.override` is what `SecureConnection` did before the default changed: a blank base plus
    /// the wrapper's own settings, whatever was declared before it discarded, silently.
    @Test
    func override_discardsEverythingDeclaredBefore() async throws {
        var expected = Internals.SecureConnection()
        expected.minimumTLSVersion = TLSVersion.v1_2.build()

        let sut = try await resolve(
            TestProperty {
                SPKIPinning {
                    SPKIHash(pin)
                }

                TrustRoots {
                    RequestDL.Certificate(certificatePath)
                }

                AdditionalTrustRoots {
                    RequestDL.Certificate(certificatePath)
                }

                Certificates {
                    RequestDL.Certificate(certificatePath)
                }

                PrivateKey(privateKeyPath, format: .pem)

                DefaultTrustRoots()

                RequestDL.SecureConnection(.override)
                    .version(minimum: .v1_2)
            }
        ).session.configuration.secureConnection

        #expect(sut == expected)
        #expect(sut?.tlsPins == nil)
        #expect(sut?.tlsPinningPolicy == nil)
        #expect(sut?.useDefaultTrustRoots == false)
    }

    @Test
    func override_withContent_discardsWhatWasDeclaredBeforeButKeepsItsOwn() async throws {
        let sut = try await resolve(
            TestProperty {
                SPKIPinning {
                    SPKIHash(pin)
                }

                RequestDL.SecureConnection(.override) {
                    TrustRoots {
                        RequestDL.Certificate(certificatePath)
                    }
                }
                .version(minimum: .v1_2)
            }
        ).session.configuration.secureConnection

        #expect(sut?.tlsPins == nil)
        #expect(sut?.trustRoots == .certificates([.init(certificatePath, format: .pem)]))
        #expect(sut?.minimumTLSVersion == TLSVersion.v1_2.build())
    }

    @Test
    func override_keepsWhatIsDeclaredAfter() async throws {
        let sut = try await resolve(
            TestProperty {
                RequestDL.SecureConnection(.override)
                    .version(minimum: .v1_2)

                SPKIPinning {
                    SPKIHash(pin)
                }
            }
        ).session.configuration.secureConnection

        #expect(sut?.tlsPins?.count == 1)
    }

    // MARK: - Cipher suites

    // `cipherSuites(_:)` only exists under `canImport(NIOCore)`.
    #if canImport(NIOCore)

    /// `cipherSuites(String...)` and `cipherSuites(TLSCipher...)` write different fields, and NIOSSL
    /// lets the `TLSCipher` list overwrite the string, so the one declared first used to win.
    @Test
    func default_whenStringCipherSuitesFollowTLSCipherValues_theLaterOneWins() async throws {
        let sut = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {}
                    .cipherSuites(.TLS_RSA_WITH_AES_128_CBC_SHA)

                RequestDL.SecureConnection {}
                    .cipherSuites("ECDHE-ECDSA-AES256-GCM-SHA384")
            }
        ).session.configuration.secureConnection

        #expect(sut?.cipherSuites == "ECDHE-ECDSA-AES256-GCM-SHA384")
        #expect(sut?.cipherSuiteValues == nil)
    }

    @Test
    func default_whenTLSCipherValuesFollowStringCipherSuites_theLaterOneWins() async throws {
        let sut = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {}
                    .cipherSuites("ECDHE-ECDSA-AES256-GCM-SHA384")

                RequestDL.SecureConnection {}
                    .cipherSuites(.TLS_RSA_WITH_AES_128_CBC_SHA)
            }
        ).session.configuration.secureConnection

        #expect(sut?.cipherSuites == nil)
        #expect(sut?.cipherSuiteValues == [TLSCipher.TLS_RSA_WITH_AES_128_CBC_SHA.build()])
    }

    @Test
    func default_whenTheSameWrapperSetsBothKindsOfCipherSuites_theLastCallWins() async throws {
        let sut = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {}
                    .cipherSuites(.TLS_RSA_WITH_AES_128_CBC_SHA)
                    .cipherSuites("ECDHE-ECDSA-AES256-GCM-SHA384")
            }
        ).session.configuration.secureConnection

        #expect(sut?.cipherSuites == "ECDHE-ECDSA-AES256-GCM-SHA384")
        #expect(sut?.cipherSuiteValues == nil)
    }

    /// The suite list that ends up in the NIOSSL configuration is the later declaration's.
    @Test
    func default_whenStringCipherSuitesFollowTLSCipherValues_theBuiltConfigurationUsesTheLaterOne() async throws {
        let sut = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {}
                    .cipherSuites(.TLS_RSA_WITH_AES_128_CBC_SHA)

                RequestDL.SecureConnection {}
                    .cipherSuites("ECDHE-ECDSA-AES256-GCM-SHA384")
            }
        ).session.configuration.secureConnection

        let built = try #require(sut).build()
        #expect(built.tlsConfiguration.cipherSuites == "ECDHE-ECDSA-AES256-GCM-SHA384")
    }
    #endif

    // MARK: - Nested

    @Test
    func nested_whenMerging_keepsWhatTheOuterOneAlreadyConfigured() async throws {
        let sut = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    SPKIPinning {
                        SPKIHash(pin)
                    }

                    RequestDL.SecureConnection {}
                        .version(minimum: .v1_3)
                }
                .verification(.noHostnameVerification)
            }
        ).session.configuration.secureConnection

        #expect(sut?.tlsPins?.count == 1)
        #expect(sut?.minimumTLSVersion == TLSVersion.v1_3.build())
        #expect(sut?.certificateVerification == CertificateVerification.noHostnameVerification.build())
    }

    /// An inner `.override` starts over from a blank configuration, the outer wrapper's own
    /// settings included, which is what nesting always did.
    @Test
    func nested_whenInnerIsOverride_discardsTheOuterOnesState() async throws {
        let sut = try await resolve(
            TestProperty {
                RequestDL.SecureConnection {
                    SPKIPinning {
                        SPKIHash(pin)
                    }

                    RequestDL.SecureConnection(.override) {}
                        .version(minimum: .v1_3)
                }
                .verification(.noHostnameVerification)
            }
        ).session.configuration.secureConnection

        #expect(sut?.tlsPins == nil)
        #expect(sut?.certificateVerification == nil)
        #expect(sut?.minimumTLSVersion == TLSVersion.v1_3.build())
    }

    @Test
    func nested_whenOuterIsOverride_stillMergesWhatIsInside() async throws {
        let sut = try await resolve(
            TestProperty {
                TrustRoots {
                    RequestDL.Certificate(certificatePath)
                }

                RequestDL.SecureConnection(.override) {
                    SPKIPinning {
                        SPKIHash(pin)
                    }

                    RequestDL.SecureConnection {}
                        .version(minimum: .v1_3)
                }
            }
        ).session.configuration.secureConnection

        #expect(sut?.trustRoots == nil)
        #expect(sut?.tlsPins?.count == 1)
        #expect(sut?.minimumTLSVersion == TLSVersion.v1_3.build())
    }
}
