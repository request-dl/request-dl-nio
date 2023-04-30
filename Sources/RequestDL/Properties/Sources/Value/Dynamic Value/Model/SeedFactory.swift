/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@RequestActor
struct SeedFactory {

    private let box = Box()

    init() {}

    func callAsFunction(_ id: Namespace.ID) -> Seed {
        let currentSeed = box.seeds[id] ?? .init(-1)
        let seed = currentSeed.next()
        box.seeds[id] = seed
        return seed
    }
}

extension SeedFactory {

    fileprivate class Box {
        var seeds = [Namespace.ID: Seed]()
    }
}
