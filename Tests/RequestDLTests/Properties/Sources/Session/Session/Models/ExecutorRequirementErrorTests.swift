//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

struct ExecutorRequirementErrorTests {

    @Test
    func error_whenRewrapped_carriesRequiredExecutorAndReasons() async throws {
        // Given
        let internalError = Internals.IncompatibleExecutorConfigurationError(
            requiredExecutor: .nioTransportServices,
            reasons: [.additionalTrustRootsUnderNetworkFramework, .certificateChain]
        )

        // When
        let error = ExecutorRequirementError(internalError)

        // Then
        #expect(error.requiredExecutor == .nioTransportServices)
        #expect(error.reasons == [.additionalTrustRootsUnderNetworkFramework, .certificateChain])
    }

    @Test
    func error_whenDescribed_namesRequiredExecutorAndEachReason() async throws {
        // Given
        let internalError = Internals.IncompatibleExecutorConfigurationError(
            requiredExecutor: .urlSession,
            reasons: [.dnsOverrideUnderURLSession, .http1OnlyUnderURLSession]
        )

        // When
        let description = ExecutorRequirementError(internalError).description

        // Then
        #expect(description.contains(".requiredExecutor(.urlSession)"))
        #expect(description.contains("DNS override"))
        #expect(description.contains("HTTP/1-only"))
        #expect(description.contains(".preferredExecutor(_:)"))
    }

    @Test(
        arguments: [
            Internals.ExecutorIncompatibilityReason.certificateChain,
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
            .proxyBearerAuthorizationUnderURLSession,
            .decompressionDisabledUnderURLSession,
        ]
    )
    func reason_whenEveryInternalCaseMapped_hasNonEmptyDescription(
        _ internalReason: Internals.ExecutorIncompatibilityReason
    ) async throws {
        // Given
        let internalError = Internals.IncompatibleExecutorConfigurationError(
            requiredExecutor: .nio,
            reasons: [internalReason]
        )

        // When
        let reason = ExecutorRequirementError(internalError).reasons[0]

        // Then
        #expect(!reason.description.isEmpty)
    }
}
