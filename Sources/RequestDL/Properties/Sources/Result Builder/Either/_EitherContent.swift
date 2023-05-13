/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
public struct _EitherContent<First: Property, Second: Property>: Property {

    private enum Source: Hashable {
        case first
        case second
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    var first: First {
        _first()
    }

    var second: Second {
        _second()
    }

    // MARK: - Private properties

    private let _first: @Sendable () -> First
    private let _second: @Sendable () -> Second

    private let source: Source

    // MARK: - Inits

    init(first: First) {
        source = .first
        _first = { first }
        _second = {
            Internals.Log.failure(
                .accessingAbstractContent()
            )
        }
    }

    init(second: Second) {
        source = .second
        _second = { second }
        _first = {
            Internals.Log.failure(
                .accessingAbstractContent()
            )
        }
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<_EitherContent<First, Second>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        switch property.source {
        case .first:
            return try await First._makeProperty(
                property: property.first,
                inputs: inputs
            )
        case .second:
            return try await Second._makeProperty(
                property: property.second,
                inputs: inputs
            )
        }
    }
}
