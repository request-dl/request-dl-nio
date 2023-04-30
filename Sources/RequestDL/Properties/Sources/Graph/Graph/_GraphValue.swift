/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@dynamicMemberLookup
@RequestActor
public struct _GraphValue<Content: Property> {

    private let content: Content

    private let id: AnyHashable
    private var nextID: AnyHashable?

    private let previousValue: IdentifiedGraphValue?

    func pointer() -> Content {
        content
    }

    static func root(_ content: Content) -> _GraphValue<Content> {
        .init(
            id: ObjectIdentifier(Content.self),
            content: content,
            previousValue: nil
        )
    }

    private init(
        id: AnyHashable,
        content: Content,
        previousValue: IdentifiedGraphValue?
    ) {
        self.id = id
        self.content = content
        self.previousValue = previousValue
        self.nextID = nil
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<Content, Value>) -> Value {
        content[keyPath: keyPath]
    }
}

extension _GraphValue {

    subscript<Next: Property>(dynamicMember keyPath: KeyPath<Content, Next>) -> _GraphValue<Next> {
        access(keyPath) {
            content[keyPath: $0]
        }
    }

    func detach<Next: Property>(_ id: AnyHashable, next: Next) -> _GraphValue<Next> {
        access(_GraphDetached(id: id)) { _ in
            next
        }
    }

    private func access<Next: Property, ID: Hashable>(
        _ id: ID,
        next: (ID) -> Next
    ) -> _GraphValue<Next> {
        var mutableSelf = self
        mutableSelf.nextID = id
        return .init(
            id: id,
            content: next(id),
            previousValue: mutableSelf._identified
        )
    }
}

private struct _GraphDetached: Hashable {
    let id: AnyHashable
}

extension _GraphValue {

    private struct Identified: IdentifiedGraphValue {
        let id: AnyHashable
        let nextID: AnyHashable?
        let previousValue: IdentifiedGraphValue?
    }

    var _identified: IdentifiedGraphValue {
        Identified(
            id: id,
            nextID: nextID,
            previousValue: previousValue
        )
    }
}

extension _GraphValue {

    var pathway: Int {
        _identified.pathway
    }

    func assertPathway() {
        _identified.assertPathway()
    }
}
