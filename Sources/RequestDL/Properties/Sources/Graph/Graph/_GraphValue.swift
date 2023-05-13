/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@dynamicMemberLookup
public struct _GraphValue<Content: Property>: Sendable {

    // MARK: - Internal properties

    var pathway: Int {
        _identified.pathway
    }

    func assertPathway() {
        _identified.assertPathway()
    }

    // MARK: - Private properties

    private let content: Content

    private let id: GraphID
    private var nextID: GraphID?

    private let previousValue: IdentifiedGraphValue?

    // MARK: - Inits

    private init(
        id: GraphID,
        content: Content,
        previousValue: IdentifiedGraphValue?
    ) {
        self.id = id
        self.content = content
        self.previousValue = previousValue
        self.nextID = nil
    }

    // MARK: - Internal static methods

    static func root(_ content: Content) -> _GraphValue<Content> {
        .init(
            id: .type(Content.self),
            content: content,
            previousValue: nil
        )
    }

    // MARK: - Internal methods

    subscript<Value>(dynamicMember keyPath: KeyPath<Content, Value>) -> Value {
        content[keyPath: keyPath]
    }

    subscript<Next: Property>(dynamicMember keyPath: KeyPath<Content, Next>) -> _GraphValue<Next> {
        access(id: .type(Next.self)) {
            $0[keyPath: keyPath]
        }
    }

    func detach<Next: Property>(
        id: GraphID = .type(Next.self),
        next: Next
    ) -> _GraphValue<Next> {
        self.access(id: id) { _ in next }
    }

    func pointer() -> Content {
        content
    }

    // MARK: - Private methods

    private func access<Next: Property>(
        id: GraphID,
        next: (Content) -> Next
    ) -> _GraphValue<Next> {
        var mutableSelf = self
        mutableSelf.nextID = id
        return .init(
            id: id,
            content: next(content),
            previousValue: mutableSelf._identified
        )
    }
}

// MARK: - IdentifiedGraphValue

extension _GraphValue {

    private struct Identified: IdentifiedGraphValue {
        let id: GraphID
        let nextID: GraphID?
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
