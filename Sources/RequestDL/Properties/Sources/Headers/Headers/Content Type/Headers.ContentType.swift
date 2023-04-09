/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Headers {

    /// A property that sets the `Content-Type` header field in an HTTP request.
    public struct ContentType: Property {

        private let contentType: RequestDL.ContentType

        /**
         Initializes a `ContentType` property with the specified content type.

         - Parameter contentType: The content type to be set in the `Content-Type` header field.
         */
        public init(_ contentType: RequestDL.ContentType) {
            self.contentType = contentType
        }

        /// Returns an exception since `Never` is a type that can never be constructed.
        public var body: Never {
            bodyException()
        }
    }
}

extension Headers.ContentType {

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Headers.ContentType>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(
            Headers.Node(
                property.contentType.rawValue,
                forKey: "Content-Type"
            )
        ))
    }
}
