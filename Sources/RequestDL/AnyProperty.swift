/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A type-erasing wrapper that can represent any `Property` instance.
public struct AnyProperty: Property {

    private let resolver: (Context) async throws -> Void

    /// Initializes a new instance of `AnyProperty` with the given property `Content`.
    public init<Content: Property>(_ property: Content) {
        resolver = {
            try await Content.makeProperty(property, $0)
        }
    }

    public var body: Never {
        bodyException()
    }

    public static func makeProperty(
        _ property: AnyProperty,
        _ context: Context
    ) async throws {
        try await property.resolver(context)
    }
}
