/*
 See LICENSE for this package's licensing information.
*/

import Foundation

struct GraphID: Hashable {

    private enum Source: Hashable {
        case identified(ObjectIdentifier)
        case constant(Int)
    }

    private let source: Source

    private init(_ source: Source) {
        self.source = source
    }

    static func type<Content>(_ type: Content.Type) -> GraphID {
        .init(.identified(.init(type)))
    }

    static func custom<Value: Hashable>(_ value: Value) -> GraphID {
        .init(.constant(value.hashValue))
    }
}
