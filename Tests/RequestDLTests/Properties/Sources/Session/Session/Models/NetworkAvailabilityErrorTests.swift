//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

struct NetworkAvailabilityErrorTests {

    @Test(arguments: [
        (Internals.NetworkPathUnsatisfiedError.Reason.noConnection, NetworkAvailabilityError.Reason.noConnection),
        (.cellularNotAllowed, .cellularNotAllowed),
        (.expensiveNotAllowed, .expensiveNotAllowed),
        (.constrainedNotAllowed, .constrainedNotAllowed),
    ])
    func error_whenInitFromInternalError_shouldMapReason(
        _ pair: (Internals.NetworkPathUnsatisfiedError.Reason, NetworkAvailabilityError.Reason)
    ) async throws {
        // Given
        let internalError = Internals.NetworkPathUnsatisfiedError(
            reason: pair.0,
            waitedForConnectivity: true
        )

        // When
        let sut = NetworkAvailabilityError(internalError)

        // Then
        #expect(sut.reason == pair.1)
        #expect(sut.waitedForConnectivity)
    }

    @Test
    func error_whenNotWaitedForConnectivity_shouldPropagateFlag() async throws {
        // Given
        let internalError = Internals.NetworkPathUnsatisfiedError(
            reason: .cellularNotAllowed,
            waitedForConnectivity: false
        )

        // When
        let sut = NetworkAvailabilityError(internalError)

        // Then
        #expect(!sut.waitedForConnectivity)
    }
}
