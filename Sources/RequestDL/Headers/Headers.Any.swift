/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Headers {

    /// A header property that accepts any value for the given key.
    public struct `Any`: Property {

        let key: String
        let value: Any

        /**
         Initializes a new instance of `Any` for the given value and key.

         - Parameters:
            - value: The value for the header property.
            - key: The key to reference the header property.
         */
        public init<S: StringProtocol>(_ value: Any, forKey key: S) {
            self.key = "\(key)"
            self.value = value
        }

        /// Returns an exception since `Never` is a type that can never be constructed.
        public var body: Never {
            bodyException()
        }
    }
}

extension Headers.`Any`: PrimitiveProperty {

    func makeObject() -> Headers.Object {
        .init(value, forKey: key)
    }
}
