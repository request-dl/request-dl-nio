/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct KeyPathNotFoundTests {

    @Test
    func error() async throws {
        // Given
        let keyPath = "any"

        // When
        let error = KeyPathNotFound(keyPath: keyPath)

        // Then
        #expect(error.errorDescription == "Unable to resolve the KeyPath.\(keyPath) in the current Task result")
    }
}
