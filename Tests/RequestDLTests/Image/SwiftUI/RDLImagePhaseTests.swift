//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(SwiftUI) && (canImport(UIKit) || canImport(AppKit))
import SwiftUI

@MainActor
struct RDLImagePhaseTests {

    private struct StubError: Error {}

    @Test
    func emptyPhaseHasNoImageOrError() {
        // Given
        let phase = RDLImagePhase.empty

        // Then
        #expect(phase.image == nil)
        #expect(phase.error == nil)
    }

    @Test
    func successPhaseExposesItsImage() {
        // Given
        let phase = RDLImagePhase.success(Image(systemName: "photo"))

        // Then
        #expect(phase.image != nil)
        #expect(phase.error == nil)
    }

    @Test
    func failurePhaseExposesItsError() {
        // Given
        let phase = RDLImagePhase.failure(StubError())

        // Then
        #expect(phase.image == nil)
        #expect(phase.error is StubError)
    }
}
#endif
