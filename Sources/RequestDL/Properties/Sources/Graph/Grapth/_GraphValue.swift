/*
 See LICENSE for this package's licensing information.
*/

import Foundation

@dynamicMemberLookup
public struct _GraphValue<Content: Property> {

    private let content: Content

    private init(_ content: Content) {
        self.content = content
    }

    subscript<Value>(dynamicMember keyPath: KeyPath<Content, Value>) -> Value {
        content[keyPath: keyPath]
    }

    subscript<Body: Property>(dynamicMember keyPath: KeyPath<Content, Body>) -> _GraphValue<Body> {
        .init(content[keyPath: keyPath])
    }

    func dynamic<Body: Property>(
        _ closure: (Content) async throws -> Body
    ) async throws -> _GraphValue<Body> {
        try await .init(closure(content))
    }

    static func root(_ content: Content) -> Self {
        .init(content)
    }
}
