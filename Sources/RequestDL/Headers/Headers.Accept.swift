/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Headers {

    /**
    A struct that represents the `Accept` header, used to specify the desired response content type for an HTTP request.
    */
    public struct Accept: Property {

        private let type: RequestDL.ContentType

        /**
         Initializes a new instance of `Accept` header for the given `ContentType`.

         - Parameter contentType: The content type to be accepted.
         */
        public init(_ contentType: RequestDL.ContentType) {
            self.type = contentType
        }

        /// Returns an exception since `Never` is a type that can never be constructed.
        public var body: Never {
            bodyException()
        }
    }
}

extension Headers.Accept {

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Headers.Accept>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(Headers.Node(
            property.type.rawValue,
            forKey: "Accept"
        )))
    }
}
