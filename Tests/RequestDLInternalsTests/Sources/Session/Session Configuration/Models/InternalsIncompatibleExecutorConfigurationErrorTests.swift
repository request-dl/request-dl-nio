//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsIncompatibleExecutorConfigurationErrorTests {

    // `.nioTransportServices` only exists under `canImport(NIOCore)`.
    #if canImport(NIOCore)
    @Test
    func error_whenHoldingRequiredExecutorAndReasons() {
        // Given
        let error = Internals.IncompatibleExecutorConfigurationError(
            requiredExecutor: .nioTransportServices,
            reasons: [.dnsOverrideUnderURLSession, .keyLogger]
        )

        // Then
        #expect(error.requiredExecutor == .nioTransportServices)
        #expect(error.reasons == [.dnsOverrideUnderURLSession, .keyLogger])
    }
    #endif

    @Test
    func error_whenReasonsEmpty() {
        // Given
        let error = Internals.IncompatibleExecutorConfigurationError(
            requiredExecutor: .urlSession,
            reasons: []
        )

        // Then
        #expect(error.reasons.isEmpty)
    }
}
