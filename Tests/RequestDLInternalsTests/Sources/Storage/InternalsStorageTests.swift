//
// See LICENSE for this package's licensing information.
//

import NIOCore
import SwiftAsyncTesting
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

@Suite(.concurrent(2), .nonFatalWatchdog)
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
        let lifetime = TimeAmount.seconds(2) + .milliseconds(500)
        let key = "key"
        let value = 1

        // When
        let storage = Internals.Storage(lifetime: lifetime)
        storage.setValue(value, forKey: key)

        // Then
        #expect(storage.getValue(Int.self, forKey: key) != nil)

        try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime.nanoseconds * 3))

        #expect(storage.getValue(Int.self, forKey: key) == nil)
    }

    @Test
    func storage_count_reflectsNumberOfEntries() async throws {
        // Given
        let storage = Internals.Storage(lifetime: Internals.Storage.lifetime)

        // Then
        #expect(storage.count == .zero)

        // When
        storage.setValue(1, forKey: "a")
        storage.setValue(2, forKey: "b")

        // Then
        #expect(storage.count == 2)
    }

    @Test
    func storage_whenValueTypeMismatches_returnsNil() async throws {
        // Given
        let storage = Internals.Storage(lifetime: Internals.Storage.lifetime)
        let key = "key"

        // When
        storage.setValue(1, forKey: key)

        // Then
        #expect(storage.getValue(String.self, forKey: key) == nil)
    }

    @Test
    func storage_setValueIfAbsent_whenKeyAlreadyOccupied_returnsExistingValue() async throws {
        // Given
        let storage = Internals.Storage(lifetime: Internals.Storage.lifetime)
        let key = "key"

        // When
        let first = storage.setValueIfAbsent(1, forKey: key)
        let second = storage.setValueIfAbsent(2, forKey: key)

        // Then
        #expect(first == 1)
        #expect(second == 1)
        #expect(storage.getValue(Int.self, forKey: key) == 1)
    }

    @Test
    func storage_whenExceedingMaximumCount_evictsOldestEntries() async throws {
        // Given
        let storage = Internals.Storage(lifetime: Internals.Storage.lifetime, maximumCount: 4)

        // When
        for index in 0..<10 {
            storage.setValue(index, forKey: "key\(index)")
        }

        // Then
        // Drops to three quarters of the ceiling (see `_evictIfNeeded`'s doc comment), so a
        // ceiling of 4 targets `max(4 - 1, 1) == 3` once eviction actually runs.
        #expect(storage.count <= 4)
        #expect(storage.count >= 3)
    }
}
