//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsHashTableTests {

    @Test
    func setAndGetTracksCount() {
        // Given
        var table = Internals.HashTable<String, Int>(capacity: 4)

        // When
        table["a"] = 1
        table["b"] = 2

        // Then
        #expect(table["a"] == 1)
        #expect(table["b"] == 2)
        #expect(table.count == 2)
    }

    @Test
    func overwritingExistingKeyUpdatesValueWithoutGrowingCount() {
        // Given
        var table = Internals.HashTable<String, Int>(capacity: 4)
        table["a"] = 1

        // When
        table["a"] = 2

        // Then
        #expect(table["a"] == 2)
        #expect(table.count == 1)
    }

    @Test
    func removingByAssigningNilDropsTheEntry() {
        // Given
        var table = Internals.HashTable<String, Int>(capacity: 4)
        table["a"] = 1

        // When
        table["a"] = nil

        // Then
        #expect(table["a"] == nil)
        #expect(table.count == 0)
    }

    @Test
    func removingAKeyThatWasNeverSetIsANoOp() {
        // Given
        var table = Internals.HashTable<String, Int>(capacity: 4)

        // When
        table["missing"] = nil

        // Then
        #expect(table.count == 0)
    }

    @Test
    func missingKeyInAnEmptyBucketReturnsNil() {
        // Given
        let table = Internals.HashTable<String, Int>(capacity: 4)

        // Then
        #expect(table["missing"] == nil)
    }

    /// All instances land in the same bucket regardless of capacity: `hash(into:)` always
    /// combines the same constant, so `_index(forKey:)` (`hashValue % capacity`) agrees for
    /// every one of them within this process. That is what is needed to force `_get`/`_remove`
    /// down their "bucket exists, but the key isn't in it" path, which a random-hash key can't
    /// reliably reach.
    private struct CollidingKey: Hashable {
        let id: Int

        static func == (lhs: CollidingKey, rhs: CollidingKey) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(0)
        }
    }

    @Test
    func missingKeyInANonEmptyCollidingBucketReturnsNil() {
        // Given
        var table = Internals.HashTable<CollidingKey, Int>(capacity: 4)
        table[CollidingKey(id: 1)] = 10
        table[CollidingKey(id: 2)] = 20

        // Then
        #expect(table[CollidingKey(id: 3)] == nil)
    }

    @Test
    func growingPastTheLoadFactorResizesWithoutLosingEntries() {
        // Given
        var table = Internals.HashTable<Int, Int>(capacity: 4)

        // When
        // Capacity 4, load factor 0.75: the 4th distinct insert (4/4 > 0.75) triggers `_resize`.
        for index in 0..<8 {
            table[index] = index * 10
        }

        // Then
        #expect(table.count == 8)
        for index in 0..<8 {
            #expect(table[index] == index * 10)
        }
    }
}
