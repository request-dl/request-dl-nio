//
// See LICENSE for this package's licensing information.
//

struct GraphID: Sendable, Hashable {

    private enum Source: Sendable, Hashable {
        case identified(ObjectIdentifier)
        // Carries the type alongside the hash, so two custom ids of different types cannot be
        // conflated by a hash that happens to match.
        case constant(ObjectIdentifier, Int)
    }

    // MARK: - Private properties

    private let source: Source

    // MARK: - Inits

    private init(_ source: Source) {
        self.source = source
    }

    // MARK: - Internal static methods

    static func type<Content>(_ type: Content.Type) -> GraphID {
        .init(.identified(.init(type)))
    }

    static func custom<Value: Hashable>(_ value: Value) -> GraphID {
        .init(.constant(.init(Value.self), value.hashValue))
    }
}
