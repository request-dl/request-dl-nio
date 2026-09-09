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
    func passes_whenNoPinsConfigured_isAlwaysTrue() throws {
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
        #expect(evaluation.passes(chain: sut))
    }

    @Test
    func passes_whenPinMismatchUnderStrictPolicy_isFalse() throws {
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
        #expect(!evaluation.passes(chain: sut))
    }

    @Test
    func passes_whenPinMismatchUnderAuditPolicy_isTrue() throws {
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
        #expect(evaluation.passes(chain: sut))
    }

    /// Regression coverage for the correctness fix folded into the `NIOTrustEvaluator`/
    /// `ServerTrustPolicy` unification: `prepare(_:skipsHostnameVerification:)` uses
    /// `SecPolicyCreateSSL(true, nil)` -- a real SSL server policy that still requires proper
    /// server-auth `extendedKeyUsage`, just without the hostname match -- not
    /// `SecPolicyCreateBasicX509()` (a bare chain-of-trust policy with no purpose/EKU checks at
    /// all), which is what `NIOTrustEvaluator`'s Network.framework closure used to build before
    /// this type existed. The fixtures' "client" certificate is self-signed with
    /// `extendedKeyUsage=clientAuth` only (no `serverAuth`) -- exactly the shape a bare X.509
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

    // MARK: - Private methods

    private static func selfSignedCertificate(_ resource: CertificateResource) throws -> [SecCertificate] {
        let der = try Data(contentsOf: resource.certificateURL)
        return [try #require(SecCertificateCreateWithData(nil, der as CFData))]
    }
}
