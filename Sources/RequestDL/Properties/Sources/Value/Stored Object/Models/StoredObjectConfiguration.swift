/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct StoredObjectConfiguration: Hashable {

    private enum Root {}

    // MARK: - Internal static properties

    static var global: Self {
        .init(
            id: .global,
            label: "_",
            seed: .zero,
            base: Root.self
        )
    }

    // MARK: - Internal properties

    let id: Namespace.ID
    let label: String
    let seed: Seed

    // MARK: - Private properties

    private let base: ObjectIdentifier

    // MARK: - Inits

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
