/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
public struct _TupleContent<T>: Property {

    private let transformHandler: (Context) async throws -> Void

    init(transform: @escaping (Context) async throws -> Void) {
        self.transformHandler = transform
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    /// This method is used internally and should not be called directly.
    public static func makeProperty(
        _ property: Self,
        _ context: Context
    ) async throws {
        try await property.transformHandler(context)
    }
}
