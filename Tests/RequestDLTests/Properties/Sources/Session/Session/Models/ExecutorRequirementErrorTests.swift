//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

struct ExecutorRequirementErrorTests {

    // `.nioTransportServices` only exists under `canImport(NIOCore)`.
    #if canImport(NIOCore)
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
    #endif

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
            .maximumTLSVersionUnderURLSession,
            .applicationProtocolsUnderURLSession,
        ]
    )
    func reason_whenEveryInternalCaseMapped_hasNonEmptyDescription(
        _ internalReason: Internals.ExecutorIncompatibilityReason
    ) async throws {
        // Given: `requiredExecutor` is incidental here -- only the reason's own description is
        // checked below -- so `.urlSession` (the one case that exists in every build) is used
        // rather than `.nio`, which doesn't exist without `canImport(NIOCore)`.
        let internalError = Internals.IncompatibleExecutorConfigurationError(
            requiredExecutor: .urlSession,
            reasons: [internalReason]
        )

        // When
        let reason = ExecutorRequirementError(internalError).reasons[0]

        // Then
        #expect(!reason.description.isEmpty)
    }
}
