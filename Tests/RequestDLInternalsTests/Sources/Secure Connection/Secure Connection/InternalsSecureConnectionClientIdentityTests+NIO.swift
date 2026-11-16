//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The client identity (`certificateChain` + `privateKey`) half of `Internals.SecureConnection`:
/// what is left of a chain when only a leaf can go out, and what a half-configured identity
/// does on each executor. None of it touches the Keychain: every case below either fails before
/// building an identity or only builds NIOSSL's.
struct InternalsSecureConnectionClientIdentityTests {

    // MARK: - Chains the Network.framework identity cannot carry

    /// `makeLocalIdentityForNetworkFramework()` only builds the `SecIdentity` from the chain's
    /// first certificate. A chain handed in as one PEM, the usual way (`Certificates("chain.pem")`
    /// or a single `Certificate` over a bundle), must be told apart from a lone leaf just as the
    /// `.certificates([a, b])` form is, or the intermediates are dropped without a word and the
    /// server rejects the handshake with `unknown_ca`.
    @Test
    func networkFrameworkIncompatibilityReasons_whenOnePEMBlobHoldsLeafAndIntermediate_reportsIt() throws {
        // Given
        let bundle = try Self.leafAndIntermediatePEM()

        var asBytes = Internals.SecureConnection()
        asBytes.certificateChain = .bytes(bundle)

        var asSingleCertificate = Internals.SecureConnection()
        asSingleCertificate.certificateChain = .certificates([Internals.Certificate(bundle, format: .pem)])

        // Premise: both really are two-certificate chains.
        #expect(try #require(asBytes.certificateChain).resolvedDERBytes().count == 2)
        #expect(try #require(asSingleCertificate.certificateChain).resolvedDERBytes().count == 2)

        // Then
        #expect(
            asBytes.networkFrameworkIncompatibilityReasons()
                .contains(.multipleClientCertificatesUnderNetworkFramework)
        )
        #expect(
            asSingleCertificate.networkFrameworkIncompatibilityReasons()
                .contains(.multipleClientCertificatesUnderNetworkFramework)
        )
    }

    @Test
    func networkFrameworkIncompatibilityReasons_whenAFileHoldsLeafAndIntermediate_reportsIt() throws {
        // Given
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("client-chain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("chain.pem")
        try Data(try Self.leafAndIntermediatePEM()).write(to: file)

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file(file.path)

        // Then
        #expect(
            secureConnection.networkFrameworkIncompatibilityReasons()
                .contains(.multipleClientCertificatesUnderNetworkFramework)
        )
    }

    @Test
    func networkFrameworkIncompatibilityReasons_whenSeveralCertificatesAreDeclaredOneByOne_reportsIt() throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .certificates([
            Internals.Certificate(try Self.pem("client_chain_leaf"), format: .pem),
            Internals.Certificate(try Self.pem("client_chain_intermediate"), format: .pem),
        ])

        // Then
        #expect(
            secureConnection.networkFrameworkIncompatibilityReasons()
                .contains(.multipleClientCertificatesUnderNetworkFramework)
        )
    }

    @Test
    func networkFrameworkIncompatibilityReasons_whenTheChainIsASingleCertificate_reportsNothing() throws {
        // Given
        let leaf = try Self.pem("client_chain_leaf")

        var asBytes = Internals.SecureConnection()
        asBytes.certificateChain = .bytes(leaf)

        var asSingleCertificate = Internals.SecureConnection()
        asSingleCertificate.certificateChain = .certificates([Internals.Certificate(leaf, format: .pem)])

        // Then
        #expect(asBytes.networkFrameworkIncompatibilityReasons().isEmpty)
        #expect(asSingleCertificate.networkFrameworkIncompatibilityReasons().isEmpty)
    }

    /// The answer is remembered, so a file is not read for every request, but a file that changed
    /// is read again.
    @Test
    func networkFrameworkIncompatibilityReasons_whenTheChainFileChanges_followsIt() throws {
        // Given
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("client-chain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let file = directory.appendingPathComponent("chain.pem")
        try Data(try Self.pem("client_chain_leaf")).write(to: file)

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file(file.path)

        // When / Then
        #expect(secureConnection.networkFrameworkIncompatibilityReasons().isEmpty)
        #expect(secureConnection.networkFrameworkIncompatibilityReasons().isEmpty)

        try Data(try Self.leafAndIntermediatePEM()).write(to: file)

        #expect(
            secureConnection.networkFrameworkIncompatibilityReasons()
                .contains(.multipleClientCertificatesUnderNetworkFramework)
        )
    }

    /// What cannot be read now is reported when the identity is built, with its own error; the
    /// compatibility check, which has no way to fail, must not hide it behind a different reason.
    @Test
    func networkFrameworkIncompatibilityReasons_whenTheChainCannotBeResolved_reportsNothing() {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file("/nonexistent/\(UUID().uuidString)/chain.pem")

        var notAPEM = Internals.SecureConnection()
        notAPEM.certificateChain = .bytes(Array("not a certificate".utf8))

        // Then
        #expect(secureConnection.networkFrameworkIncompatibilityReasons().isEmpty)
        #expect(notAPEM.networkFrameworkIncompatibilityReasons().isEmpty)
    }

    // MARK: - Half a client identity

    /// A certificate with no key (or the reverse) is a configuration mistake. `.urlSession` and
    /// `.nioTransportServices` already refuse it; `.nio`, the only executor off Darwin, used to
    /// send the request without any client certificate and without a word.
    @Test
    func build_whenOnlyTheCertificateIsConfigured_throwsUnderNIOSSL() throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .bytes(try Self.pem("client_chain_leaf"))

        // Then
        #expect(throws: Internals.SecureConnection.ConfigurationError.incompleteClientIdentity) {
            _ = try secureConnection.build(isCompatibleWithNetworkFramework: false)
        }
    }

    @Test
    func build_whenOnlyThePrivateKeyIsConfigured_throwsUnderNIOSSL() throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.privateKey = .privateKey(.init(try Self.privateKeyPEM("client_chain_leaf"), format: .pem))

        // Then
        #expect(throws: Internals.SecureConnection.ConfigurationError.incompleteClientIdentity) {
            _ = try secureConnection.build(isCompatibleWithNetworkFramework: false)
        }
    }

    /// A proxied client does its TLS with NIOSSL even on a Network.framework event loop, so the
    /// NIOSSL identity is the one that is built, and the one that must be complete.
    @Test
    func build_whenOnlyTheCertificateIsConfiguredAndTheClientIsProxied_throws() throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .bytes(try Self.pem("client_chain_leaf"))

        // Then
        #expect(throws: Internals.SecureConnection.ConfigurationError.incompleteClientIdentity) {
            _ = try secureConnection.build(isCompatibleWithNetworkFramework: true, isProxied: true)
        }
    }

    @Test
    func build_whenNoClientIdentityIsConfigured_buildsUnderNIOSSL() throws {
        // Given
        let secureConnection = Internals.SecureConnection()

        // Then
        _ = try secureConnection.build(isCompatibleWithNetworkFramework: false)
    }

    @Test
    func build_whenTheClientIdentityIsComplete_buildsUnderNIOSSL() throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .bytes(try Self.pem("client_chain_leaf"))
        secureConnection.privateKey = .privateKey(.init(try Self.privateKeyPEM("client_chain_leaf"), format: .pem))

        // Then
        _ = try secureConnection.build(isCompatibleWithNetworkFramework: false)
    }

    #if canImport(Darwin)
    @Test
    func build_whenOnlyHalfOfTheClientIdentityIsConfigured_throwsUnderNetworkFramework() throws {
        // Given
        var onlyCertificate = Internals.SecureConnection()
        onlyCertificate.certificateChain = .bytes(try Self.pem("client_chain_leaf"))

        var onlyPrivateKey = Internals.SecureConnection()
        onlyPrivateKey.privateKey = .privateKey(.init(try Self.privateKeyPEM("client_chain_leaf"), format: .pem))

        // Then
        #expect(throws: Internals.URLSessionIdentityPolicy.ConfigurationError.self) {
            _ = try onlyCertificate.build(isCompatibleWithNetworkFramework: true)
        }
        #expect(throws: Internals.URLSessionIdentityPolicy.ConfigurationError.self) {
            _ = try onlyPrivateKey.build(isCompatibleWithNetworkFramework: true)
        }
    }

    /// What the executor choice sees, not only the reasons: a chain with an intermediate in one
    /// PEM keeps Network.framework from being picked, even when it is asked for, and from being
    /// forced.
    @Test
    func
        resolveExecutor_whenNetworkFrameworkIsEnabledAndTheChainIsOnePEMWithAnIntermediate_doesNotPickNetworkFramework()
        throws
    {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.enableNetworkFramework = true

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .bytes(try Self.leafAndIntermediatePEM())
        configuration.secureConnection = secureConnection

        // Then: `.urlSession` sends the intermediates, so it is what is left.
        #expect(configuration.resolveExecutor() == .urlSession)
    }

    @Test
    func requireExecutor_whenNIOTransportServicesIsPinnedAndTheChainIsOnePEMWithAnIntermediate_throws() throws {
        // Given
        var configuration = Internals.Session.Configuration()

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .bytes(try Self.leafAndIntermediatePEM())
        configuration.secureConnection = secureConnection

        // Then
        #expect(throws: Internals.IncompatibleExecutorConfigurationError.self) {
            try configuration.requireExecutor(.nioTransportServices)
        }
    }
    #endif

    @Test
    func configurationError_whenIncompleteClientIdentity_describesItself() {
        // Given
        let error = Internals.SecureConnection.ConfigurationError.incompleteClientIdentity

        // Then
        #expect(error.errorDescription == error.description)
        #expect(error.description.contains("certificateChain and a privateKey"))
    }

    /// More chains than the cache holds: the answer stays right when it starts over.
    @Test
    func networkFrameworkIncompatibilityReasons_whenMoreChainsThanTheCacheHolds_stillAnswersEachOne() throws {
        // Given
        let leaf = try Self.pem("client_chain_leaf")
        let bundle = try Self.leafAndIntermediatePEM()

        // Then
        for index in 0..<80 {
            var single = Internals.SecureConnection()
            single.certificateChain = .bytes(leaf + [UInt8](repeating: 0x0A, count: index))

            var chain = Internals.SecureConnection()
            chain.certificateChain = .bytes(bundle + [UInt8](repeating: 0x0A, count: index))

            #expect(single.networkFrameworkIncompatibilityReasons().isEmpty)
            #expect(
                chain.networkFrameworkIncompatibilityReasons()
                    .contains(.multipleClientCertificatesUnderNetworkFramework)
            )
        }
    }

    // MARK: - Helpers

    private static func pem(_ name: String) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: CertificateResource(name, format: .pem).certificateURL))
    }

    private static func privateKeyPEM(_ name: String) throws -> [UInt8] {
        [UInt8](try Data(contentsOf: CertificateResource(name, format: .pem).privateKeyURL))
    }

    private static func leafAndIntermediatePEM() throws -> [UInt8] {
        try pem("client_chain_leaf") + [0x0A] + pem("client_chain_intermediate")
    }
}

#endif
