/*
 See LICENSE for this package's licensing information.
 */

import Foundation

public struct _PropertyInputs {

    private let root: ObjectIdentifier
    private let id: AnyHashable
    private let body: ObjectIdentifier
    var environment: EnvironmentValues

    init<Root: Property, ID: Hashable, Body: Property>(
        root: Root.Type,
        id: ID,
        body: KeyPath<Root, Body>,
        environment: EnvironmentValues = .init()
    ) {
        self.root = ObjectIdentifier(root)
        self.id = id
        self.body = ObjectIdentifier(Body.self)
        self.environment = environment
    }

    subscript<Root: Property, ID: Hashable, Body: Property>(
        root: Root.Type,
        id: ID,
        body: KeyPath<Root, Body>
    ) -> _PropertyInputs {
        precondition(self.body == ObjectIdentifier(root))

        var inputs = _PropertyInputs(
            root: root,
            id: id,
            body: body
        )
        inputs.environment = environment
        return inputs
    }
}

extension _PropertyInputs {

    init<Root: Property, Body: Property>(
        root: Root.Type,
        body: KeyPath<Root, Body>,
        environment: EnvironmentValues = .init()
    ) {
        self.init(
            root: root,
            id: ObjectIdentifier(Body.self),
            body: body,
            environment: environment
        )
    }

    init<Root: Property>(
        root: Root.Type,
        environment: EnvironmentValues = .init()
    ) {
        self.init(
            root: root,
            body: \.body,
            environment: environment
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
