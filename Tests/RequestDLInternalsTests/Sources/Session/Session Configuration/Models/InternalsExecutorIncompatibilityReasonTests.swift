//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsExecutorIncompatibilityReasonTests {

    @Test
    func reason_whenEquals() {
        // Given
        let lhs = Internals.ExecutorIncompatibilityReason.certificateChain
        let rhs = Internals.ExecutorIncompatibilityReason.certificateChain

        // Then
        #expect(lhs == rhs)
    }

    @Test
    func reason_whenNotEquals() {
        // Given
        let lhs = Internals.ExecutorIncompatibilityReason.certificateChain
        let rhs = Internals.ExecutorIncompatibilityReason.privateKey

        // Then
        #expect(lhs != rhs)
    }

    @Test
    func reason_whenHashable() {
        // Given
        let cases: Set<Internals.ExecutorIncompatibilityReason> = [
            .certificateChain,
            .privateKey,
            .keyLogger,
            .cipherSuites,
            .cipherSuiteValues,
            .renegotiationSupport,
            .signingSignatureAlgorithms,
            .verifySignatureAlgorithms,
            .sendCANameList,
            .shutdownTimeout,
            .pskHint,
            .pskIdentityResolver,
            .noHostnameVerificationUnderNetworkFramework,
            .additionalTrustRootsUnderNetworkFramework,
            .dnsOverrideUnderURLSession,
            .http1OnlyUnderURLSession,
            .proxyConnectHeadersUnderURLSession,
            .proxySOCKSUnderURLSession,
            .proxyBearerAuthorizationUnderURLSession,
            .decompressionDisabledUnderURLSession,
        ]

        // Then
        #expect(cases.count == 20)
    }
}
