//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

struct SeedFactory: Sendable {

    private final class Storage: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _seeds = [PropertyNamespace.ID: Seed]()

        // MARK: - Internal methods

        /// Hands out the next seed for `id`.
        ///
        /// Reading, incrementing and writing happen in one critical section. Reaching the
        /// dictionary through a computed property with a lock on each accessor made this three
        /// separate acquisitions, so two callers asking at the same time both read the same
        /// value and both walked away with the same seed. Since the seed keys stored object
        /// identity, that means two distinct properties pointing at the same state, which is
        /// the one outcome a seed factory exists to prevent.
        func next(_ id: PropertyNamespace.ID) -> Seed {
            lock.withLock {
                let seed = _seeds[id]?.next() ?? .zero
                _seeds[id] = seed
                return seed
            }
        }
    }

    // MARK: - Private properties

    private let storage = Storage()

    // MARK: - Inits

    init() {}

    // MARK: - Internal methods

    func callAsFunction(_ id: PropertyNamespace.ID) -> Seed {
        storage.next(id)
    }
}
