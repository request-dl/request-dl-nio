/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@dynamicMemberLookup
public struct _GraphValue<Content: Property> {

    private let id: AnyHashable
    private let content: Content

    fileprivate let previous: _RawGraphValue?
    fileprivate var next: AnyHashable?

    func pointer() -> Content {
        content
    }

    static func root(_ content: Content) -> _GraphValue<Content> {
        .init(
            id: ObjectIdentifier(Content.self),
            content: content,
            previous: nil
        )
    }

    private init(
        id: AnyHashable,
        content: Content,
        previous: _RawGraphValue?
    ) {
        self.id = id
        self.content = content
        self.previous = previous
        self.next = nil
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
        mutableSelf.next = id
        return .init(
            id: id,
            content: next(id),
            previous: mutableSelf
        )
    }
}

private protocol _RawGraphValue {

    var previous: _RawGraphValue? { get }
    var next: AnyHashable? { get }

    func assertNext(_ id: AnyHashable)
}

extension _GraphValue: _RawGraphValue {

    fileprivate func assertNext(_ id: AnyHashable) {
        if next == id {
            return
        }

        Internals.Log.failure(
            .unexpectedGraphPathway()
        )
    }
}

private struct _GraphDetached: Hashable {
    let id: AnyHashable
}

extension _GraphValue {

    func assertPathway() {
        previous?.assertNext(id)
    }

    var pathwayHashValue: Int {
        sequence(first: self as _RawGraphValue, next: { $0.previous })
            .map(\.next)
            .hashValue
    }
}
