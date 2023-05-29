/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct SeedFactory: Sendable {

    private final class Storage: @unchecked Sendable {

        // MARK: - Internal properties

        var seeds: [PropertyNamespace.ID: Seed] {
            get { lock.withLock { _seeds } }
            set { lock.withLock { _seeds = newValue } }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _seeds = [PropertyNamespace.ID: Seed]()
    }

    // MARK: - Private properties

    private let storage = Storage()

    // MARK: - Inits

    init() {}

    // MARK: - Internal methods

    func callAsFunction(_ id: PropertyNamespace.ID) -> Seed {
        let currentSeed = storage.seeds[id] ?? .init(-1)
        let seed = currentSeed.next()
        storage.seeds[id] = seed
        return seed
    }
}
