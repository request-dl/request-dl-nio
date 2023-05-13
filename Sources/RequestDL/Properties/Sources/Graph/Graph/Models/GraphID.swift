/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct GraphID: Sendable, Hashable {

    private enum Source: Sendable, Hashable {
        case identified(ObjectIdentifier)
        case constant(Int)
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
        .init(.constant(value.hashValue))
    }
}
