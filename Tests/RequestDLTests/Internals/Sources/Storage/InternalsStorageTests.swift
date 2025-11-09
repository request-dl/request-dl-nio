/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct InternalsStorageTests {

    @Test
    func storage_whenSetValue() async throws {
        // Given
        let key = "key"
        let value = 1
        let storage = Internals.Storage.shared

        // When
        storage.setValue(value, forKey: key)

        // Then
        #expect(storage.getValue(Int.self, forKey: key) == value)
    }

    @Test
    func storage_whenExpiredLifetime() async throws {
        // Given
        let lifetime: UInt64 = 2_500_000_000
        let key = "key"
        let value = 1

        // When
        let storage = Internals.Storage(lifetime: lifetime)
        storage.setValue(value, forKey: key)

        // Then
        #expect(storage.getValue(Int.self, forKey: key) != nil)

        try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime * 3))

        #expect(storage.getValue(Int.self, forKey: key) == nil)
    }
}
