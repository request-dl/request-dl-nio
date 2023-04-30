/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct StoredObjectConfiguration: Hashable {
    let namespaceID: Namespace.ID
    let pathway: Int
    let label: String

    private let base: ObjectIdentifier

    init<Base>(
        namespaceID: Namespace.ID,
        base: Base.Type,
        pathway: Int,
        label: String
    ) {
        self.namespaceID = namespaceID
        self.base = .init(base)
        self.pathway = pathway
        self.label = label
    }
}

extension StoredObjectConfiguration {

    private enum Root {}

    static var global: Self {
        .init(
            namespaceID: .global,
            base: Root.self,
            pathway: .zero,
            label: "_"
        )
    }
}
