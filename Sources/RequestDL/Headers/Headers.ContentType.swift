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

extension Headers.ContentType: PrimitiveProperty {

    func makeObject() -> Headers.Object {
        .init(contentType.rawValue, forKey: "Content-Type")
    }
}
