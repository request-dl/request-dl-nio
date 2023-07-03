/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
public struct _EitherContent<First: Property, Second: Property>: Property {

    private enum Source {
        case first(First)
        case second(Second)
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let source: Source

    // MARK: - Inits

    init(first: First) {
        source = .first(first)
    }

    init(second: Second) {
        source = .second(second)
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<_EitherContent<First, Second>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        switch property.source {
        case .first(let first):
            return try await First._makeProperty(
                property: property.detach(next: first),
                inputs: inputs
            )
        case .second(let second):
            return try await Second._makeProperty(
                property: property.detach(next: second),
                inputs: inputs
            )
        }
    }
}
