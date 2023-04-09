/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
public struct _EitherContent<First: Property, Second: Property>: Property {

    private let _first: () -> First
    private let _second: () -> Second

    private let source: Source

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

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension _EitherContent {

    var first: First {
        _first()
    }

    var second: Second {
        _second()
    }
}

extension _EitherContent {

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<_EitherContent<First, Second>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        switch property.source {
        case .first:
            return try await First._makeProperty(
                property: property.first,
                inputs: inputs[self, \.first]
            )
        case .second:
            return try await Second._makeProperty(
                property: property.second,
                inputs: inputs[self, \.second]
            )
        }
    }
}

extension _EitherContent {

    fileprivate enum Source {
        case first
        case second
    }
}
