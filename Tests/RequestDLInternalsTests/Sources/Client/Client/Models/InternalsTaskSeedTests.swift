//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDLInternals

struct InternalsTaskSeedTests {

    @Test
    func callAsFunctionCancelsOnlyOnce() {
        // Given
        let cancelCount = InlineProperty(wrappedValue: 0)
        var seed: Internals.TaskSeed? = Internals.TaskSeed(
            cancel: { cancelCount.wrappedValue += 1 },
            release: {}
        )

        // When
        seed?()
        seed?()

        // Then
        #expect(cancelCount.wrappedValue == 1)

        // Cleanup: already claimed, so deinit below must not call `release` a second time.
        seed = nil
    }

    @Test
    func deinitAfterCallAsFunctionDoesNotAlsoRelease() {
        // Given
        let cancelCount = InlineProperty(wrappedValue: 0)
        let releaseCount = InlineProperty(wrappedValue: 0)
        var seed: Internals.TaskSeed? = Internals.TaskSeed(
            cancel: { cancelCount.wrappedValue += 1 },
            release: { releaseCount.wrappedValue += 1 }
        )

        // When
        seed?()
        seed = nil

        // Then
        #expect(cancelCount.wrappedValue == 1)
        #expect(releaseCount.wrappedValue == 0)
    }

    @Test
    func deinitWithoutCallAsFunctionReleases() {
        // Given
        let releaseCount = InlineProperty(wrappedValue: 0)
        var seed: Internals.TaskSeed? = Internals.TaskSeed(
            cancel: {},
            release: { releaseCount.wrappedValue += 1 }
        )
        #expect(seed != nil)

        // When
        seed = nil

        // Then
        #expect(releaseCount.wrappedValue == 1)
    }

    @Test
    func equalityIsIdentityBased() {
        // Given
        let first = Internals.TaskSeed {}
        let second = Internals.TaskSeed {}

        // Then
        #expect(first == first)
        #expect(first != second)
    }

    @Test
    func hashableAllowsUseAsSetMember() {
        // Given
        let first = Internals.TaskSeed {}
        let second = Internals.TaskSeed {}

        // When
        let set: Set<Internals.TaskSeed> = [first, first, second]

        // Then
        #expect(set.count == 2)
    }
}
