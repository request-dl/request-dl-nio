/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Headers {

    /// A property that sets the `Content-Type` header field in an HTTP request.
    @available(*, deprecated, message: "ContentType has been moved to internal logic of Payload and Forms")
    public struct ContentType: Property {

        // MARK: - Public properties

        /// Returns an exception since `Never` is a type that can never be constructed.
        public var body: Never {
            bodyException()
        }

        // MARK: - Private properties

        private let contentType: RequestDL.ContentType

        // MARK: - Inits

        /**
         Initializes a `ContentType` property with the specified content type.

         - Parameter contentType: The content type to be set in the `Content-Type` header field.
         */
        public init(_ contentType: RequestDL.ContentType) {
            self.contentType = contentType
        }

        // MARK: - Public static methods

        /// This method is used internally and should not be called directly.
        public static func _makeProperty(
            property: _GraphValue<Headers.ContentType>,
            inputs: _PropertyInputs
        ) async throws -> _PropertyOutputs {
            property.assertPathway()
            return .leaf(
                Headers.Node(
                    key: "Content-Type",
                    value: property.contentType.rawValue
                )
            )
        }
    }
}
