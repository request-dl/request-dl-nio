/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Headers {

    /// A header property that accepts any value for the given key.
    public struct `Any`: Property {

        let key: String
        let value: String

        /**
         Initializes a new instance of `Headers.Any` for the given value and name.

         - Parameters:
            - name: The name to reference the header property.
            - value: The value for the header property.
         */
        public init<Name: StringProtocol, Value: StringProtocol>(
            name: Name,
            value: Value
        ) {
            self.key = String(name)
            self.value = String(value)
        }

        /**
         Initializes a new instance of `Headers.Any` for the given value and name.

         - Parameters:
            - name: The name to reference the header property.
            - value: The value for the header property.
         */
        public init<Name: StringProtocol, Value: LosslessStringConvertible>(
            name: Name,
            value: Value
        ) {
            self.key = String(name)
            self.value = String(value)
        }

        /// Returns an exception since `Never` is a type that can never be constructed.
        public var body: Never {
            bodyException()
        }
    }
}

extension Headers.`Any` {

    /**
     Initializes a new instance of `Any` for the given value and key.

     - Parameters:
        - value: The value for the header property.
        - key: The key to reference the header property.
     */
    @available(*, deprecated, message: "Prefers the string init")
    public init<S: StringProtocol>(_ value: Any, forKey key: S) {
        self.key = String(key)
        self.value = "\(value)"
    }
}

extension Headers.`Any` {

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Headers.`Any`>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Headers.Node(
            key: property.key,
            value: property.value
        ))
    }
}
