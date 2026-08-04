//
// See LICENSE for this package's licensing information.
//

@dynamicMemberLookup
public struct _GraphValue<Content: Property>: Sendable {

    // MARK: - Internal properties

    let pathway: Int

    func assertPathway() {
        _identified.assertPathway()
    }

    // MARK: - Private properties

    private let content: Content

    private let id: GraphID
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
        self.pathway = Identified.pathway(id: id, previousValue: previousValue)
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

    public subscript<Value>(dynamicMember keyPath: KeyPath<Content, Value>) -> Value {
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
        .init(
            id: id,
            content: next(content),
            // The link the child will assert against is built here, rather than by mutating a
            // throwaway copy of `self`. `nextID` was a stored `var` that no reachable value
            // ever carried: `access` set it on a copy, used it, and dropped it, so every
            // `_GraphValue` anyone could hold reported `nil`.
            previousValue: Identified(
                id: self.id,
                nextID: id,
                pathway: pathway,
                previousValue: previousValue
            )
        )
    }
}

// MARK: - IdentifiedGraphValue

extension _GraphValue {

    fileprivate struct Identified: IdentifiedGraphValue {
        let id: GraphID
        let nextID: GraphID?
        let pathway: Int
        let previousValue: IdentifiedGraphValue?
    }

    var _identified: IdentifiedGraphValue {
        Identified(
            id: id,
            nextID: nil,
            pathway: pathway,
            previousValue: previousValue
        )
    }
}
