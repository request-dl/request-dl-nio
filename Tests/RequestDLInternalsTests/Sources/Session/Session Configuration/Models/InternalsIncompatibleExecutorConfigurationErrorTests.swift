//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsIncompatibleExecutorConfigurationErrorTests {

    @Test
    func error_whenHoldingRequiredExecutorAndReasons() {
        // Given
        let error = Internals.IncompatibleExecutorConfigurationError(
            requiredExecutor: .nioTransportServices,
            reasons: [.additionalTrustRootsUnderNetworkFramework, .certificateChain]
        )

        // Then
        #expect(error.requiredExecutor == .nioTransportServices)
        #expect(error.reasons == [.additionalTrustRootsUnderNetworkFramework, .certificateChain])
    }

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
