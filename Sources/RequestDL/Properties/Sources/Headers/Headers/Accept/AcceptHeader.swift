/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
A struct that represents the `AcceptHeader` header, used to specify the desired response
content type for an HTTP request.
*/
public struct AcceptHeader: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let type: RequestDL.ContentType

    // MARK: - Inits

    /**
     Initializes a new instance of `Accept` header for the given `ContentType`.

     - Parameter contentType: The content type to be accepted.
     */
    public init(_ contentType: RequestDL.ContentType) {
        self.type = contentType
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<AcceptHeader>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(HeaderNode(
            key: "Accept",
            value: property.type.rawValue,
            strategy: inputs.environment.headerStrategy,
            separator: inputs.environment.headerSeparator
        ))
    }
}
