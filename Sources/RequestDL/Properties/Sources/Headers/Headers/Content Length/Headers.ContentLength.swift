/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Headers {

    /// A type representing the Content-Length header in an HTTP message.
    public struct ContentLength: Property {

        // MARK: - Public properties

        /// Returns an exception since `Never` is a type that can never be constructed.
        public var body: Never {
            bodyException()
        }

        // MARK: - Private properties

        private let bytes: Int

        // MARK: - Inits

        /**
         Initializes a `ContentLength` instance with the specified number of bytes.

         - Parameter bytes: The number of bytes in the message body.
         */
        public init(_ bytes: Int) {
            self.bytes = bytes
        }

        // MARK: - Public static methods

        /// This method is used internally and should not be called directly.
        public static func _makeProperty(
            property: _GraphValue<Headers.ContentLength>,
            inputs: _PropertyInputs
        ) async throws -> _PropertyOutputs {
            property.assertPathway()
            return .leaf(Headers.Node(
                key: "Content-Length",
                value: String(property.bytes)
            ))
        }
    }
}
