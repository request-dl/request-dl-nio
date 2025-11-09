/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct KeyPathInvalidDataErrorTests {

    @Test
    func error() async throws {
        // Given
        let error = KeyPathInvalidDataError()

        // Then
        #expect(error.errorDescription == """
            Unable to read the current data result on Task.keyPath() in key-value format
            """
        )
    }
}
