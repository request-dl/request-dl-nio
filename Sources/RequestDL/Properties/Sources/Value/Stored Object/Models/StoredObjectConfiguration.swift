/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct StoredObjectConfiguration: Hashable {

    let id: Namespace.ID
    let label: String
    let seed: Seed

    private let base: ObjectIdentifier

    init<Base>(
        id: Namespace.ID,
        label: String,
        seed: Seed,
        base: Base.Type
    ) {
        self.id = id
        self.label = label
        self.seed = seed
        self.base = .init(base)
    }
}

extension StoredObjectConfiguration {

    private enum Root {}

    static var global: Self {
        .init(
            id: .global,
            label: "_",
            seed: .zero,
            base: Root.self
        )
    }
}
