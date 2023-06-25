/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 Sets the `Accept-Charset` header in the request.

 This is a specific feature that should be explored according to the needs of each endpoint. JSON in Swift, for
 example, uses `UTF-8`, `UTF-16`, and `UTF-32` during decoding and fails if other charsets are used.
 Therefore, always use this option only if it is truly necessary.
*/
public struct AcceptCharsetHeader: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let charset: Charset

    // MARK: - Inits

    /**
     Initializes a new instance for the given `Charset`.

     - Parameter charset: The charset to be accepted. Defaults is UTF-8.
     */
    public init(_ charset: Charset) {
        self.charset = charset
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<AcceptCharsetHeader>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(HeaderNode(
            key: "Accept-Charset",
            value: property.charset.rawValue,
            strategy: inputs.environment.headerStrategy
        ))
    }
}
