//
// See LICENSE for this package's licensing information.
//

import Security
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct InternalsDarwinTrustEvaluationTests {

    @Test
    func evaluate_whenNoPinsConfigured_isAlwaysTrue() throws {
        // Given -- nothing to pin against, so chain validity (already confirmed by the caller's
        // own SecTrustEvaluate... call before this runs) is the whole check.
        let evaluation = Internals.DarwinTrustEvaluation(trustRootCertificates: [], pins: [], isStrict: true)

        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(
            try Self.selfSignedCertificate(Certificates(.der).server()) as CFArray,
            SecPolicyCreateBasicX509(),
            &trust
        )
        let sut = try #require(status == errSecSuccess ? trust : nil)

        // When / Then
        #expect(evaluation.evaluate(chain: sut, chainIsTrusted: true))
    }

    @Test
    func evaluate_whenChainNotTrusted_isFalseRegardlessOfPins() throws {
        // Given -- the caller's own `SecTrustEvaluate...` already rejected the chain; no pin
        // configuration should be able to override that.
        let evaluation = Internals.DarwinTrustEvaluation(trustRootCertificates: [], pins: [], isStrict: false)

        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(
            try Self.selfSignedCertificate(Certificates(.der).server()) as CFArray,
            SecPolicyCreateBasicX509(),
            &trust
        )
        let sut = try #require(status == errSecSuccess ? trust : nil)

        // When / Then
        #expect(!evaluation.evaluate(chain: sut, chainIsTrusted: false))
    }

    @Test
    func evaluate_whenPinMismatchUnderStrictPolicy_isFalse() throws {
        // Given
        let unrelatedPin = Internals.ResolvedSPKIPin { _ in false }
        let evaluation = Internals.DarwinTrustEvaluation(
            trustRootCertificates: [],
            pins: [unrelatedPin],
            isStrict: true
        )

        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(
            try Self.selfSignedCertificate(Certificates(.der).server()) as CFArray,
            SecPolicyCreateBasicX509(),
            &trust
        )
        let sut = try #require(status == errSecSuccess ? trust : nil)

        // When / Then
        #expect(!evaluation.evaluate(chain: sut, chainIsTrusted: true))
    }

    @Test
    func evaluate_whenPinMismatchUnderAuditPolicy_isTrue() throws {
        // Given -- `.audit` only ever relaxes a pin mismatch, matching `ServerTrustPolicy`'s own
        // longstanding semantics.
        let unrelatedPin = Internals.ResolvedSPKIPin { _ in false }
        let evaluation = Internals.DarwinTrustEvaluation(
            trustRootCertificates: [],
            pins: [unrelatedPin],
            isStrict: false
        )

        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(
            try Self.selfSignedCertificate(Certificates(.der).server()) as CFArray,
            SecPolicyCreateBasicX509(),
            &trust
        )
        let sut = try #require(status == errSecSuccess ? trust : nil)

        // When / Then
        #expect(evaluation.evaluate(chain: sut, chainIsTrusted: true))
    }

    @Test
    func evaluate_notifiesObserverWithTheSameOutcomeAndPinMatchState() throws {
        // Given -- the observer must see exactly the accept/reject decision (and pin-match state)
        // `evaluate(chain:chainIsTrusted:)` itself returns, not some separately recomputed value.
        let unrelatedPin = Internals.ResolvedSPKIPin { _ in false }
        let observer = RecordingTrustDecisionObserver()
        let evaluation = Internals.DarwinTrustEvaluation(
            trustRootCertificates: [],
            pins: [unrelatedPin],
            isStrict: true,
            observer: observer
        )

        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(
            try Self.selfSignedCertificate(Certificates(.der).server()) as CFArray,
            SecPolicyCreateBasicX509(),
            &trust
        )
        let sut = try #require(status == errSecSuccess ? trust : nil)

        // When
        let accepted = evaluation.evaluate(chain: sut, chainIsTrusted: true)

        // Then
        #expect(observer.decisions.count == 1)
        #expect(observer.decisions.first?.isTrusted == accepted)
        #expect(observer.decisions.first?.pinsMatched == false)
    }

    @Test
    func evaluate_whenChainNotTrusted_notifiesObserverWithNilPinsMatched() throws {
        // Given -- a broken chain never gets far enough to consult pins at all.
        let observer = RecordingTrustDecisionObserver()
        let evaluation = Internals.DarwinTrustEvaluation(
            trustRootCertificates: [],
            pins: [Internals.ResolvedSPKIPin { _ in true }],
            isStrict: true,
            observer: observer
        )

        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(
            try Self.selfSignedCertificate(Certificates(.der).server()) as CFArray,
            SecPolicyCreateBasicX509(),
            &trust
        )
        let sut = try #require(status == errSecSuccess ? trust : nil)

        // When
        _ = evaluation.evaluate(chain: sut, chainIsTrusted: false)

        // Then
        #expect(observer.decisions == [TrustDecision(isTrusted: false, pinsMatched: nil)])
    }

    /// Regression coverage for the correctness fix folded into the `NIOTrustEvaluator`/
    /// `ServerTrustPolicy` unification: `prepare(_:skipsHostnameVerification:)` uses
    /// `SecPolicyCreateSSL(true, nil)`, a real SSL server policy that still requires proper
    /// server-auth `extendedKeyUsage`, just without the hostname match, rather than
    /// `SecPolicyCreateBasicX509()` (a bare chain-of-trust policy with no purpose/EKU checks at
    /// all), which is what `NIOTrustEvaluator`'s Network.framework closure used to build before
    /// this type existed. The fixtures' "client" certificate is self-signed with
    /// `extendedKeyUsage=clientAuth` only (no `serverAuth`): exactly the shape a bare X.509
    /// policy would still accept but a real SSL server policy correctly rejects.
    @Test
    func prepare_whenSkipsHostnameVerification_stillEnforcesServerAuthExtendedKeyUsage() throws {
        // Given
        let certificate = try Self.selfSignedCertificate(Certificates(.der).client())

        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate as CFArray, SecPolicyCreateBasicX509(), &trust)
        let sut = try #require(status == errSecSuccess ? trust : nil)

        let evaluation = Internals.DarwinTrustEvaluation(
            trustRootCertificates: certificate,
            pins: [],
            isStrict: false
        )

        // When -- self-anchored on its own (self-signed) certificate, so the only reason this
        // could still fail is a policy check beyond bare chain-of-trust.
        evaluation.prepare(sut, skipsHostnameVerification: true)

        // Then -- a bare X.509 policy would accept this outright; a real SSL server policy
        // rejects it for lacking the serverAuth EKU.
        var evaluationError: CFError?
        let isTrusted = SecTrustEvaluateWithError(sut, &evaluationError)
        #expect(!isTrusted)
    }

    /// Regression coverage for `prepare(_:skipsHostnameVerification:)`'s revocation-policy
    /// composition: `SecTrustSetPolicies` replaces a trust's whole policy array rather than
    /// appending to it, so appending a revocation policy without first reading the trust's
    /// existing array back via `SecTrustCopyPolicies` would silently drop the base SSL/X.509
    /// policy `SecTrustCreateWithCertificates` installed it with. This asserts the array grows
    /// by exactly one rather than being replaced outright.
    @Test
    func prepare_whenRevocationPolicyConfiguredWithoutSkippingHostnameVerification_appendsToExistingPolicies() throws {
        // Given
        let certificate = try Self.selfSignedCertificate(Certificates(.der).server())

        var trust: SecTrust?
        let status = SecTrustCreateWithCertificates(certificate as CFArray, SecPolicyCreateBasicX509(), &trust)
        let sut = try #require(status == errSecSuccess ? trust : nil)

        var policiesBefore: CFArray?
        _ = SecTrustCopyPolicies(sut, &policiesBefore)
        let countBefore = (policiesBefore as? [SecPolicy])?.count ?? 0

        let evaluation = Internals.DarwinTrustEvaluation(
            trustRootCertificates: [],
            pins: [],
            isStrict: true,
            revocationPolicy: .strict
        )

        // When
        evaluation.prepare(sut, skipsHostnameVerification: false)

        // Then
        var policiesAfter: CFArray?
        _ = SecTrustCopyPolicies(sut, &policiesAfter)
        let countAfter = (policiesAfter as? [SecPolicy])?.count ?? 0

        #expect(countAfter == countBefore + 1)
    }

    // MARK: - Private methods

    private static func selfSignedCertificate(_ resource: CertificateResource) throws -> [SecCertificate] {
        let der = try Data(contentsOf: resource.certificateURL)
        return [try #require(SecCertificateCreateWithData(nil, der as CFData))]
    }
}

/// A test double recording every ``TrustDecision`` it's notified of, in order. `@unchecked
/// Sendable` is safe here, since every test in this file calls `evaluate(chain:chainIsTrusted:)`
/// synchronously, from a single thread, never concurrently.
private final class RecordingTrustDecisionObserver: TrustDecisionObserver, @unchecked Sendable {
    private(set) var decisions: [TrustDecision] = []

    func callAsFunction(_ decision: TrustDecision) {
        decisions.append(decision)
    }
}
