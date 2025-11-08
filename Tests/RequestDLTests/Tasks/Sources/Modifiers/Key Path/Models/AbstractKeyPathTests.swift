/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct AbstractKeyPathTests {

    @Test
    func keyPath() async throws {
        // Given
        func getValue(_ keyPath: KeyPath<AbstractKeyPath, String>) -> String {
            AbstractKeyPath()[keyPath: keyPath]
        }

        // When
        let keyPath = getValue(\.results)

        // Then
        #expect(keyPath == "results")
    }
}
