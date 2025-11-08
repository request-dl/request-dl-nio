/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InvalidStatusCodeErrorTests {

    @Test
    func error() async throws {
        // Given
        let error = InvalidStatusCodeError(data: true)

        // Then
        #expect(error.data)
    }
}
