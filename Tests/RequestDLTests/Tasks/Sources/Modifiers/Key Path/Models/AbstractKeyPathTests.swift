//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(Darwin)
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
#endif
