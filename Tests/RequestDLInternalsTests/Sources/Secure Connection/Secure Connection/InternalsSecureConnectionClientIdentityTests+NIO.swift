//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import Testing

#if canImport(Security)
import Security
#endif

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The client identity (`certificateChain` + `privateKey`) half of `Internals.SecureConnection`:
/// that a chain with intermediates no longer rules Network.framework out, what the identity
/// handle carries of it, and what a half-configured identity does on each executor.
struct InternalsSecureConnectionClientIdentityTests {

    // MARK: - Chains with intermediates

    /// Network.framework presents the intermediates next to the identity
    /// (`tlsLocalIdentityChainProviderNetworkFramework`), so a chain of several certificates is
    /// no reason to leave it, however it was handed in: one PEM (`Certificates("chain.pem")` or a
    /// single `Certificate` over a bundle), a file, or declared one certificate at a time.
    @Test
    func networkFrameworkIncompatibilityReasons_whenTheChainHasIntermediates_reportsNothing() throws {
        // Given
        let bundle = try Self.leafAndIntermediatePEM()

        var asBytes = Internals.SecureConnection()
        asBytes.certificateChain = .bytes(bundle)

        var asSingleCertificate = Internals.SecureConnection()
        asSingleCertificate.certificateChain = .certificates([Internals.Certificate(bundle, format: .pem)])

        var declaredOneByOne = Internals.SecureConnection()
        declaredOneByOne.certificateChain = .certificates([
            Internals.Certificate(try Self.pem("client_chain_leaf"), format: .pem),
            Internals.Certificate(try Self.pem("client_chain_intermediate"), format: .pem),
        ])

        // Premise: all three really are two-certificate chains.
        #expect(try #require(asBytes.certificateChain).resolvedDERBytes().count == 2)
        #expect(try #require(asSingleCertificate.certificateChain).resolvedDERBytes().count == 2)
        #expect(try #require(declaredOneByOne.certificateChain).resolvedDERBytes().count == 2)

        // Then
        #expect(asBytes.networkFrameworkIncompatibilityReasons().isEmpty)
        #expect(asSingleCertificate.networkFrameworkIncompatibilityReasons().isEmpty)
        #expect(declaredOneByOne.networkFrameworkIncompatibilityReasons().isEmpty)
    }

    @Test
    func networkFrameworkIncompatibilityReasons_whenAFileHoldsLeafAndIntermediate_reportsNothing() throws {
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
        #expect(secureConnection.networkFrameworkIncompatibilityReasons().isEmpty)
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

    /// What cannot be read now is reported when the identity is built, with its own error; the
    /// compatibility check, which has no way to fail, never hides it behind a different reason.
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
    /// PEM no longer keeps Network.framework from being picked when it is asked for, or from
    /// being forced.
    @Test
    func resolveExecutor_whenNetworkFrameworkIsEnabledAndTheChainIsOnePEMWithAnIntermediate_picksNetworkFramework()
        throws
    {
        // Given
        var configuration = Internals.Session.Configuration()
        configuration.enableNetworkFramework = true

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .bytes(try Self.leafAndIntermediatePEM())
        configuration.secureConnection = secureConnection

        // Then
        #expect(configuration.resolveExecutor() == .nioTransportServices)
    }

    @Test
    func requireExecutor_whenNIOTransportServicesIsPinnedAndTheChainIsOnePEMWithAnIntermediate_doesNotThrow() throws {
        // Given
        var configuration = Internals.Session.Configuration()

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .bytes(try Self.leafAndIntermediatePEM())
        configuration.secureConnection = secureConnection

        // Then
        try configuration.requireExecutor(.nioTransportServices)
    }

    // MARK: - The identity handle carries the intermediates

    /// The leaf is the identity; what follows it travels beside it, without the leaf and in the
    /// order the chain was written, which is what `sec_identity_create_with_certificates` expects.
    @Test
    func build_whenTheChainHasIntermediates_theIdentityHandleCarriesThemWithoutTheLeaf() throws {
        // Given
        let leaf = try Self.pem("client_chain_leaf")
        let intermediate = try Self.pem("client_chain_intermediate")
        let root = try Self.pem("client_chain_root")

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .bytes(leaf + [0x0A] + intermediate + [0x0A] + root)
        secureConnection.privateKey = .privateKey(.init(try Self.privateKeyPEM("client_chain_leaf"), format: .pem))

        let chain = try #require(secureConnection.certificateChain).resolvedDERBytes()

        // When
        let output = try secureConnection.build(isCompatibleWithNetworkFramework: true)

        // Then
        let handle = try #require(output.localIdentityHandle)
        let presented = handle.certificates.map { Data(SecCertificateCopyData($0) as Data) }

        #expect(chain.count == 3)
        #expect(presented == Array(chain.dropFirst()))
        #expect(!presented.contains(chain[0]))

        var identityCertificate: SecCertificate?
        #expect(SecIdentityCopyCertificate(handle.identity, &identityCertificate) == errSecSuccess)
        #expect(identityCertificate.map { Data(SecCertificateCopyData($0) as Data) } == chain[0])
    }

    @Test
    func build_whenTheChainIsTheLeafAlone_theIdentityHandleCarriesNoIntermediates() throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .bytes(try Self.pem("client_chain_leaf"))
        secureConnection.privateKey = .privateKey(.init(try Self.privateKeyPEM("client_chain_leaf"), format: .pem))

        // When
        let output = try secureConnection.build(isCompatibleWithNetworkFramework: true)

        // Then
        #expect(try #require(output.localIdentityHandle).certificates.isEmpty)
    }

    /// An intermediate that is not a certificate fails the build with its own error instead of
    /// being dropped, which would present a chain the server cannot complete.
    @Test
    func build_whenAnIntermediateIsNotACertificate_throws() throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .certificates([
            Internals.Certificate(try Self.pem("client_chain_leaf"), format: .pem),
            Internals.Certificate([0x30, 0x03, 0x02, 0x01, 0x01], format: .der),
        ])
        secureConnection.privateKey = .privateKey(.init(try Self.privateKeyPEM("client_chain_leaf"), format: .pem))

        // Then
        #expect(throws: (any Error).self) {
            _ = try secureConnection.build(isCompatibleWithNetworkFramework: true)
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
