/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Headers {

    /// A type representing the Content-Length header in an HTTP message.
    public struct ContentLength: Property {

        private let bytes: Int

        /**
         Initializes a `ContentLength` instance with the specified number of bytes.

         - Parameter bytes: The number of bytes in the message body.
         */
        public init(_ bytes: Int) {
            self.bytes = bytes
        }

        /// Returns an exception since `Never` is a type that can never be constructed.
        public var body: Never {
            bodyException()
        }
    }
}

extension Headers.ContentLength: PrimitiveProperty {

    func makeObject() -> Headers.Object {
        .init(bytes, forKey: "Content-Length")
    }
}
