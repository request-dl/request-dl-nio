//
// See LICENSE for this package's licensing information.
//

// `Internals.NIOTrustEvaluator` only exists under `canImport(NIOCore)`; `.urlSession` has its
// own separate trust-evaluation path (`Internals.DarwinTrustEvaluation`/`ServerTrustPolicy`).
#if canImport(NIOCore)

import Crypto
import NIOCore
import NIOPosix
import NIOSSL
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Tests `Internals.NIOTrustEvaluator` against a real, `openssl`-generated and
/// `openssl verify`-checked three-level certificate chain (root CA -> intermediate CA -> leaf),
/// not mocks, so a broken chain genuinely fails to validate and a matching SPKI pin genuinely
/// hashes to the configured digest. Covers the behavior this type exists for: pinning the
/// intermediate (not just the leaf) matches, a pin mismatch only rejects under `.strict`, and a
/// broken chain rejects unconditionally regardless of policy.
struct InternalsNIOTrustEvaluatorTests {

    @Test
    func resolve_whenNothingConfigured_returnsNil() throws {
        // Given: SPKI pinning is the trigger this file's own chain-validation tests exercise,
        // but it's not the only one: on Darwin, `additionalTrustRoots`/`.noHostnameVerification`
        // alone also install this evaluator (see `InternalsSecureConnectionTests`'s
        // `secureConnection_whenNetworkFrameworkReachableFieldSet_remainsCompatible` for that).
        // With none of the three configured at all, though, no custom verification is installed,
        // so the TLS backend's own native trust-root handling stays untouched.
        let secureConnection = Internals.SecureConnection()

        // Then
        #expect(try Internals.NIOTrustEvaluator.resolve(from: secureConnection) == nil)
    }

    #if canImport(Darwin)
    @Test
    func resolve_whenOnlyRevocationPolicyConfigured_installsEvaluator() throws {
        // Given: NIOSSL/BoringSSL implements no revocation checking of its own, so this only
        // ever installs the custom-verification evaluator on Darwin, the same way
        // `additionalTrustRoots`/`.noHostnameVerification` alone do (see
        // `resolve_whenNothingConfigured_returnsNil` above).
        var secureConnection = Internals.SecureConnection()
        secureConnection.revocationPolicy = .strict

        // Then
        #expect(try Internals.NIOTrustEvaluator.resolve(from: secureConnection) != nil)
    }

    private final class NoOpTrustDecisionObserver: TrustDecisionObserver, @unchecked Sendable {
        func callAsFunction(_ decision: TrustDecision) {}
    }

    @Test
    func resolve_whenOnlyObserverConfigured_installsEvaluator() throws {
        // Given: the observer alone is a reason to install custom verification on Darwin, even
        // with every other trigger left at its default.
        var secureConnection = Internals.SecureConnection()
        secureConnection.trustDecisionObserver = NoOpTrustDecisionObserver()

        // Then
        #expect(try Internals.NIOTrustEvaluator.resolve(from: secureConnection) != nil)
    }

    /// Regression coverage for `NIOTrustEvaluator+Darwin`'s plain (non-Network.framework)
    /// `tlsCustomVerification` closure: it used to build its from-scratch `SecTrust` with
    /// `SecPolicyCreateBasicX509()`, a bare chain-of-trust policy with no purpose/EKU checks at
    /// all. Because this closure always passes `skipsHostnameVerification: false` to
    /// `DarwinTrustEvaluation.prepare`, that method's own policy swap to a real SSL policy never
    /// triggered here (its `skipsHostnameVerification` branch never runs, and its
    /// `revocationPolicy` branch only *appends* to the existing, still-EKU-less array) — so a
    /// certificate lacking the server-auth `extendedKeyUsage` was silently accepted whenever this
    /// evaluator was installed (e.g. by SPKI pinning), unlike the equivalent
    /// `.urlSession`/Network.framework paths. See `InternalsDarwinTrustEvaluationTests`'s
    /// `prepare_whenSkipsHostnameVerification_stillEnforcesServerAuthExtendedKeyUsage`, which
    /// documents the same fix having already been made for the Network.framework closure.
    @Test
    func tlsCustomVerification_whenLeafLacksServerAuthExtendedKeyUsage_rejects() async throws {
        // Given: a self-signed certificate with `extendedKeyUsage=clientAuth` only (no
        // `serverAuth`) — the same fixture proven elsewhere to be accepted by a bare X.509 policy
        // but rejected by a real SSL server policy. Self-signed, so it's also its own trust
        // anchor: only a purpose/EKU check can still fail this chain.
        let pemBytes = try Array(Data(contentsOf: Certificates(.pem).client().certificateURL))

        var secureConnection = Internals.SecureConnection()
        secureConnection.trustRoots = .certificates([.init(pemBytes, format: .pem)])
        // An unrelated pin under `.audit` installs the evaluator without making the outcome
        // depend on a pin match (already covered by `tlsCustomVerification_whenPinMismatch...`
        // above) or on network-dependent revocation checking, isolating this test to the EKU
        // check alone.
        secureConnection.tlsPins = [.init(source: .base64String(Self.unrelatedPinBase64), algorithm: SHA256.self)]
        secureConnection.tlsPinningPolicy = .audit

        let evaluator = try #require(try Internals.NIOTrustEvaluator.resolve(from: secureConnection))
        let certificate = try NIOSSLCertificate(bytes: pemBytes, format: .pem)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let promise = group.next().makePromise(of: NIOSSLVerificationResult.self)

        // When
        evaluator.tlsCustomVerification([certificate], promise)

        // Then
        let result = try await promise.futureResult.get()
        try await group.shutdownGracefully()

        #expect(result == .failed)
    }
    #endif

    @Test
    func tlsCustomVerification_whenPinningLeaf_acceptsChain() async throws {
        try await assertVerification(pinningBase64: Self.leafSPKIPinBase64, expectVerified: true)
    }

    @Test
    func tlsCustomVerification_whenPinningIntermediate_acceptsChain() async throws {
        // The whole point of leaf+intermediate pinning (OWASP's recommended backup-pin practice):
        // a pin on the intermediate, which rotates far less often than the leaf, matches too.
        try await assertVerification(pinningBase64: Self.intermediateSPKIPinBase64, expectVerified: true)
    }

    @Test
    func tlsCustomVerification_whenPinMismatchUnderStrictPolicy_rejects() async throws {
        try await assertVerification(pinningBase64: Self.unrelatedPinBase64, policy: .strict, expectVerified: false)
    }

    @Test
    func tlsCustomVerification_whenPinMismatchUnderAuditPolicy_stillAccepts() async throws {
        try await assertVerification(pinningBase64: Self.unrelatedPinBase64, policy: .audit, expectVerified: true)
    }

    @Test
    func tlsCustomVerification_whenTrustRootNotConfigured_rejectsRegardlessOfPolicy() async throws {
        // The self-signed test root isn't in the real system trust store, so chain validation
        // itself fails when it's never installed as a trust anchor here, and that must reject
        // even under `.audit`, which only ever relaxes a *pin* mismatch, never a broken chain.
        try await assertVerification(
            pinningBase64: Self.leafSPKIPinBase64,
            policy: .audit,
            includeTrustRoot: false,
            expectVerified: false
        )
    }

    // MARK: - Private methods

    private func assertVerification(
        pinningBase64: String,
        policy: Internals.SPKIPinningPolicy = .strict,
        includeTrustRoot: Bool = true,
        expectVerified: Bool
    ) async throws {
        var secureConnection = Internals.SecureConnection()
        if includeTrustRoot {
            secureConnection.trustRoots = .certificates([.init(Array(Self.rootPEM.utf8), format: .pem)])
        }
        secureConnection.tlsPins = [.init(source: .base64String(pinningBase64), algorithm: SHA256.self)]
        secureConnection.tlsPinningPolicy = policy

        let evaluator = try #require(try Internals.NIOTrustEvaluator.resolve(from: secureConnection))

        let leaf = try NIOSSLCertificate(bytes: Array(Self.leafPEM.utf8), format: .pem)
        let intermediate = try NIOSSLCertificate(bytes: Array(Self.intermediatePEM.utf8), format: .pem)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let promise = group.next().makePromise(of: NIOSSLVerificationResult.self)

        evaluator.tlsCustomVerification([leaf, intermediate], promise)

        let result = try await promise.futureResult.get()
        try await group.shutdownGracefully()

        #expect((result == .certificateVerified) == expectVerified)
    }

    // MARK: - Test fixtures
    //
    // A real chain, generated with openssl and confirmed with `openssl verify -CAfile root.crt
    // -untrusted intermediate.crt leaf.crt` before being pasted in here. Root and intermediate
    // are P-256, the intermediate has `basicConstraints=critical,CA:TRUE,pathlen:0`, and the leaf
    // has `basicConstraints=critical,CA:FALSE` with `extendedKeyUsage=serverAuth`.

    private static let rootPEM = """
        -----BEGIN CERTIFICATE-----
        MIIBMDCB2AIJAJn1z1LZ3C5OMAoGCCqGSM49BAMCMCExHzAdBgNVBAMMFlJlcXVl
        c3RETCBUZXN0IFJvb3QgQ0EwHhcNMjYwOTA4MjI0MjUzWhcNMzYwOTA1MjI0MjUz
        WjAhMR8wHQYDVQQDDBZSZXF1ZXN0REwgVGVzdCBSb290IENBMFkwEwYHKoZIzj0C
        AQYIKoZIzj0DAQcDQgAEoF93a/3YNMpbMWInI3+vSci+u8AOQ/U/UkYkqSaB1gzm
        0jPvRqtVxO84OT+l+7rsjMtr3Bq7pQNi3pVJvZYsZTAKBggqhkjOPQQDAgNHADBE
        AiBRoOg8Bc4+QBFM+WF/ISad8cbUPYYpokhcOb9NAaDTRQIgZa8nv6eTKug1jLEc
        ZfhyirOmWGAvNaGKd1f0Nsg3fV0=
        -----END CERTIFICATE-----
        """

    private static let intermediatePEM = """
        -----BEGIN CERTIFICATE-----
        MIIBZjCCAQ2gAwIBAgIJAMSyavHobm5wMAoGCCqGSM49BAMCMCExHzAdBgNVBAMM
        FlJlcXVlc3RETCBUZXN0IFJvb3QgQ0EwHhcNMjYwOTA4MjI0MjUzWhcNMzEwOTA3
        MjI0MjUzWjApMScwJQYDVQQDDB5SZXF1ZXN0REwgVGVzdCBJbnRlcm1lZGlhdGUg
        Q0EwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAT5bjXBe2Yy0yokxdnPtb15xXuY
        qe0uXVrkbJ68tWzZFvddbSdbzBTBl+JtJM5EzTtq+UdrYSn9NrlaejoTRSm8oyYw
        JDASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBBjAKBggqhkjOPQQD
        AgNHADBEAiBZu3vsZhCHabe7HEg1G+ihwpUB9CqxBtU6dkUYt1lsFAIgPgEoFhv8
        4OxDy7akMrmhjYF8tss+3Egp2chJHt7HjoI=
        -----END CERTIFICATE-----
        """

    private static let leafPEM = """
        -----BEGIN CERTIFICATE-----
        MIIBjjCCATOgAwIBAgIJAI7yfkO2eqn0MAoGCCqGSM49BAMCMCkxJzAlBgNVBAMM
        HlJlcXVlc3RETCBUZXN0IEludGVybWVkaWF0ZSBDQTAeFw0yNjA5MDgyMjQyNTNa
        Fw0yODEyMTEyMjQyNTNaMBsxGTAXBgNVBAMMEGxlYWYuZXhhbXBsZS5jb20wWTAT
        BgcqhkjOPQIBBggqhkjOPQMBBwNCAATJWysghI3r7ZYFneo8Dnvp8PcCgg97NYsR
        +74XzDpHLTiqSohx+D0v2G0vvGP7kmAxrrtoO8RyD2ne2bQAhPaxo1IwUDAMBgNV
        HRMBAf8EAjAAMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDATAb
        BgNVHREEFDASghBsZWFmLmV4YW1wbGUuY29tMAoGCCqGSM49BAMCA0kAMEYCIQCl
        mCofAAWSYQ7ePRnKPgMY+SIIj0rdmKZglhiNYCvrsQIhALJVr92AyseZbc4Mkopg
        L8EpopmdnbqqsW7jzb1SL9mC
        -----END CERTIFICATE-----
        """

    /// `openssl x509 -in leaf.crt -pubkey -noout | openssl pkey -pubin -outform der | openssl
    /// dgst -sha256 -binary | base64`, computed independently of any code under test.
    private static let leafSPKIPinBase64 = "IikJpHu0p+Tm4dpFCXRFXMkLLYsRjwePLjgvHYMYnJw="

    /// Same recipe as `leafSPKIPinBase64`, run against `intermediate.crt`.
    private static let intermediateSPKIPinBase64 = "0715ggkh3Sde/vilUaD01AjS05rQT2NopWpK584Krrc="

    /// `openssl rand -base64 32`, doesn't match any certificate in the chain, on purpose.
    private static let unrelatedPinBase64 = "tH0BF9jVlk3y2e1huTk41UtsPgrhf4cFbJLczhAfH3g="
}

#endif
