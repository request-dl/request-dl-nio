/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct SeedFactory: Sendable {

    // MARK: - Private properties

    private let storage = Storage()

    // MARK: - Inits

    init() {}

    // MARK: - Internal methods

    func callAsFunction(_ id: Namespace.ID) -> Seed {
        let currentSeed = storage.seeds[id] ?? .init(-1)
        let seed = currentSeed.next()
        storage.seeds[id] = seed
        return seed
    }
}

extension SeedFactory {

    fileprivate final class Storage: @unchecked Sendable {

        // MARK: - Internal properties

        var seeds: [Namespace.ID: Seed] {
            get { lock.withLock { _seeds } }
            set { lock.withLock { _seeds = newValue } }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _seeds = [Namespace.ID: Seed]()
    }
}
