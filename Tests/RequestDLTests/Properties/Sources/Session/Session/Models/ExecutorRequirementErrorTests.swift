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
            reasons: [.dnsOverrideUnderURLSession, .keyLogger]
        )

        // When
        let error = ExecutorRequirementError(internalError)

        // Then
        #expect(error.requiredExecutor == .nioTransportServices)
        #expect(error.reasons == [.dnsOverrideUnderURLSession, .keyLogger])
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
            Internals.ExecutorIncompatibilityReason.keyLogger,
            .cipherSuites,
            .cipherSuiteValues,
            .renegotiationSupport,
            .signingSignatureAlgorithms,
            .verifySignatureAlgorithms,
            .sendCANameList,
            .shutdownTimeout,
            .pskHint,
            .pskIdentityResolver,
            .dnsOverrideUnderURLSession,
            .http1OnlyUnderURLSession,
            .proxyConnectHeadersUnderURLSession,
            .proxyBearerAuthorizationUnderURLSession,
            .decompressionRequiresURLSession,
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

    @Test
    func reason_additionalTrustRootsUnderNetworkFramework_hasNonEmptyDescription() async throws {
        // Given -- kept for source compatibility even though RequestDLInternals no longer
        // produces this case (see its own doc comment); not reachable through
        // `reason_whenEveryInternalCaseMapped_hasNonEmptyDescription` above since there's no
        // longer an `Internals.ExecutorIncompatibilityReason` counterpart to map from.

        // Then
        #expect(!ExecutorRequirementError.Reason.additionalTrustRootsUnderNetworkFramework.description.isEmpty)
    }

    @Test
    func reason_noHostnameVerificationUnderNetworkFramework_hasNonEmptyDescription() async throws {
        // Given -- same situation as `additionalTrustRootsUnderNetworkFramework` above: kept for
        // source compatibility, no longer produced, no longer reachable through the parameterized
        // test above.

        // Then
        #expect(!ExecutorRequirementError.Reason.noHostnameVerificationUnderNetworkFramework.description.isEmpty)
    }
}
