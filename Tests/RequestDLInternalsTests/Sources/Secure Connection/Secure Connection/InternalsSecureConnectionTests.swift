//
// See LICENSE for this package's licensing information.
//

import Crypto
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

/// Only the tests that never call `secureConnection.build()` (only exists under
/// `canImport(NIOCore)`, returns an AsyncHTTPClient `TLSConfiguration`) and never touch the
/// `keyLogger`/`pskIdentityResolver`/`pskHint` properties (also gated the same way, since
/// `SSLKeyLogger`/`SSLPSKIdentityResolver` themselves need NIOSSL) stay here. The rest live in
/// `InternalsSecureConnectionTests+NIO.swift`.
struct InternalsSecureConnectionTests {

    @Test
    func secureConnection_whenDefaultTrustNotSet_shouldBeFalse() async throws {
        // Given
        let secureConnection = Internals.SecureConnection()
        // Then
        #expect(!secureConnection.useDefaultTrustRoots)
    }

    @Test
    func secureConnection_whenSetDefaultTrust() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        // When
        secureConnection.useDefaultTrustRoots = true

        // Then
        #expect(secureConnection.useDefaultTrustRoots)
    }

    @Test
    func secureConnection_whenEquals() async throws {
        // Given
        let lhs = Internals.SecureConnection()
        let rhs = Internals.SecureConnection()

        // Then
        #expect(lhs == rhs)
    }

    @Test
    func secureConnection_whenNotEquals() async throws {
        // Given
        var lhs = Internals.SecureConnection()
        var rhs = Internals.SecureConnection()

        // When
        lhs.maximumTLSVersion = .tlsv12
        rhs.maximumTLSVersion = .tlsv13

        // Then
        #expect(lhs != rhs)
    }
}

extension InternalsSecureConnectionTests {

    @Test
    func secureConnection_whenDefault_isCompatibleWithNetworkFramework() async throws {
        // Given
        let secureConnection = Internals.SecureConnection()

        // Then
        #if canImport(Darwin)
        #expect(secureConnection.isCompatibleWithNetworkFramework)
        #else
        #expect(!secureConnection.isCompatibleWithNetworkFramework)
        #endif
    }

    /// mTLS (`certificateChain`/`privateKey`), SPKI pinning (`tlsPins`), `additionalTrustRoots`,
    /// and `.noHostnameVerification` all reach Network.framework: mTLS through
    /// `tlsLocalIdentityNetworkFramework`, and the other three through
    /// `Internals.NIOTrustEvaluator` installing `tlsCustomVerificationNetworkFramework` on its own,
    /// independently of whether SPKI pinning is also configured. `skipsHostnameVerification`
    /// additionally swaps in a hostname-less trust policy for the `.noHostnameVerification` case
    /// specifically.
    ///
    /// Mirrors `secureConnection_whenURLSessionReachableFieldSet_remainsCompatible` below, but for
    /// the Network.framework-facing reason list.
    @Test(
        arguments: [
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.certificateChain = .certificates([])
                secureConnection.privateKey = .privateKey(.init([], format: .pem))
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.tlsPins = [.init(source: .rawData(.init()), algorithm: SHA256.self)]
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.additionalTrustRoots = [.file("/dev/null")]
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.certificateVerification = .noHostnameVerification
            },
        ] as [@Sendable (inout Internals.SecureConnection) -> Void]
    )
    func secureConnection_whenNetworkFrameworkReachableFieldSet_remainsCompatible(
        _ mutate: @Sendable (inout Internals.SecureConnection) -> Void
    ) async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        // When
        mutate(&secureConnection)

        // Then: `networkFrameworkIncompatibilityReasons()` (the platform-independent logic this
        // test actually exercises), not `isCompatibleWithNetworkFramework` (which is unconditionally
        // `false` off Darwin regardless of reasons, since Network.framework doesn't exist there at
        // all; see `secureConnection_whenDefault_isCompatibleWithNetworkFramework` above).
        #expect(secureConnection.networkFrameworkIncompatibilityReasons().isEmpty)
    }

    @Test
    func secureConnection_whenDefault_urlSessionIncompatibilityReasonsIsEmpty() async throws {
        // Given
        let secureConnection = Internals.SecureConnection()

        // Then
        #expect(secureConnection.urlSessionIncompatibilityReasons().isEmpty)
    }

    /// Executor compatibility is not a strict hierarchy, made concrete: these four fields are
    /// excluded from `networkFrameworkIncompatibilityReasons()`'s counterpart list but reachable under
    /// URLSession (via a Keychain round-trip for the identity fields, `SecTrust`/`SecPolicy` for
    /// trust roots and hostname verification), so they must never appear in the URLSession
    /// reason list.
    @Test(
        arguments: [
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.certificateVerification = .noHostnameVerification
            },
            { (secureConnection: inout Internals.SecureConnection) in
                secureConnection.additionalTrustRoots = [.file("/dev/null")]
            },
        ] as [@Sendable (inout Internals.SecureConnection) -> Void]
    )
    func secureConnection_whenURLSessionReachableFieldSet_remainsCompatible(
        _ mutate: @Sendable (inout Internals.SecureConnection) -> Void
    ) async throws {
        // Given
        var secureConnection = Internals.SecureConnection()

        // When
        mutate(&secureConnection)

        // Then
        #expect(secureConnection.urlSessionIncompatibilityReasons().isEmpty)
    }

    /// `buildURLSessionConfiguration()` maps `maximumTLSVersion` straight onto
    /// `URLSessionConfiguration.tlsMaximumSupportedProtocolVersion`, so flagging it here would
    /// force every such session onto NIO despite `.urlSession` handling it natively -- the same
    /// class of bug already ruled out for `minimumTLSVersion` right below. A prior version of
    /// this check incorrectly did flag it, making that mapping permanently unreachable.
    @Test
    func secureConnection_whenMaximumTLSVersionSet_remainsCompatible() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.maximumTLSVersion = .tlsv12

        // Then
        #expect(!secureConnection.urlSessionIncompatibilityReasons().contains(.maximumTLSVersionUnderURLSession))
        #expect(secureConnection.urlSessionIncompatibilityReasons().isEmpty)
    }

    @Test
    func secureConnection_whenApplicationProtocolsSet_urlSessionIncompatibilityReasonsContainsIt() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.applicationProtocols = ["h2"]

        // Then
        #expect(secureConnection.urlSessionIncompatibilityReasons().contains(.applicationProtocolsUnderURLSession))
    }

    /// `minimumTLSVersion` is deliberately excluded from `urlSessionIncompatibilityReasons()`,
    /// like its sibling `maximumTLSVersion` above. It is carried under `.urlSession` by
    /// `URLSessionConfiguration.tlsMinimumSupportedProtocolVersion`, so it must never force a
    /// fallback away from `.urlSession` or trip `requiredExecutor(.urlSession)`.
    @Test
    func secureConnection_whenMinimumTLSVersionSet_remainsCompatibleWithURLSession() async throws {
        // Given
        var secureConnection = Internals.SecureConnection()
        secureConnection.minimumTLSVersion = .tlsv12

        // Then
        #expect(secureConnection.urlSessionIncompatibilityReasons().isEmpty)
    }

    /// What `==` decides is whether `Internals.ClientManager` hands a pooled client back for a
    /// configuration it was not built for, so every field that changes the TLS handshake has to
    /// be in it.
    ///
    /// Constructed directly rather than through the `Property` layer on purpose: no public path
    /// can currently set `useDefaultTrustRoots` apart from `trustRoots`, which is exactly why
    /// leaving it out of `==` went unnoticed. This pins the invariant before a path that can
    /// arrives.
    @Test
    func secureConnection_whenOnlyUseDefaultTrustRootsDiffers_shouldNotCompareEqual() async throws {
        // Given
        let withoutDefaultTrustRoots = Internals.SecureConnection()

        var withDefaultTrustRoots = Internals.SecureConnection()
        withDefaultTrustRoots.useDefaultTrustRoots = true

        // Then
        #expect(withoutDefaultTrustRoots != withDefaultTrustRoots)
        #expect(withoutDefaultTrustRoots == Internals.SecureConnection())
    }
}
