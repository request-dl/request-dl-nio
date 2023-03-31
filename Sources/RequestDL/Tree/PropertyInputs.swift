/*
 See LICENSE for this package's licensing information.
 */

import Foundation

public struct _PropertyInputs {

    private let root: ObjectIdentifier
    private let id: AnyHashable
    private let body: ObjectIdentifier

    init<Root: Property, ID: Hashable, Body: Property>(
        root: Root.Type,
        id: ID,
        body: KeyPath<Root, Body>
    ) {
        self.root = ObjectIdentifier(root)
        self.id = id
        self.body = ObjectIdentifier(Body.self)
    }

    subscript<Root: Property, ID: Hashable, Body: Property>(
        root: Root.Type,
        id: ID,
        body: KeyPath<Root, Body>
    ) -> _PropertyInputs {
        precondition(self.body == ObjectIdentifier(root))
        return _PropertyInputs(
            root: root,
            id: id,
            body: body
        )
    }
}

extension _PropertyInputs {

    init<Root: Property, Body: Property>(
        root: Root.Type,
        body: KeyPath<Root, Body>
    ) {
        self.init(
            root: root,
            id: ObjectIdentifier(Body.self),
            body: body
        )
    }

    init<Root: Property>(root: Root.Type) {
        self.init(
            root: root,
            body: \.body
        )
    }
}

extension _PropertyInputs {

    subscript<Root: Property, Body: Property>(
        root: Root.Type,
        body: KeyPath<Root, Body>
    ) -> _PropertyInputs {
        self[root, ObjectIdentifier(Body.self), body]
    }

    subscript<Root: Property>(_ root: Root.Type) -> _PropertyInputs {
        self[root, \.body]
    }
}
