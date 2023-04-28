/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Headers {

    /// A header property that accepts any value for the given key.
    @RequestActor
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

extension Headers.`Any` {

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<Headers.`Any`>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .init(Leaf(Headers.Node(
            property.value,
            forKey: property.key
        )))
    }
}
