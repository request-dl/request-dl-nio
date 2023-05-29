/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A header property that accepts custom value for the given key.
public struct CustomHeader: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let key: String
    let value: String

    // MARK: - Inits

    /**
     Initializes a new instance of `CustomHeader` for the given value and name.

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
     Initializes a new instance of `CustomHeader` for the given value and name.

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

    // MARK: - Public static methods

    public static func _makeProperty(
        property: _GraphValue<CustomHeader>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(HeaderNode(
            key: property.key,
            value: property.value,
            strategy: inputs.environment.headerStrategy
        ))
    }
}

@available(*, deprecated)
extension Headers {

    @available(*, deprecated, renamed: "CustomHeader")
    public typealias `Any` = CustomHeader
}

// MARK: - Deprecated

extension CustomHeader {

    /**
     Initializes a new instance of `CustomHeader` for the given value and key.

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