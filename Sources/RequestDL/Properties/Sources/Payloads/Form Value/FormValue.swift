/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// `FormValue` is a type of property that represents a single value in a multipart form-data request
///
/// It can be used to represent simple values like strings and numbers.
public struct FormValue: Property {

    let key: String
    let value: String

    /**
     Creates a new instance of `FormValue` to represent a value with a corresponding key in a form.

     The value parameter is the actual value to be sent, and key is the reference key used to identify
     the value when the form is submitted.

     - Parameters:
        - key: The key used to reference the value in the form.
        - value: The value to be sent.
     */
    public init<Key: StringProtocol, Value: StringProtocol>(
        key: Key,
        value: Value
    ) {
        self.key = String(key)
        self.value = String(value)
    }

    /**
     Creates a new instance of `FormValue` to represent a value with a corresponding key in a form.

     The value parameter is the actual value to be sent, and key is the reference key used to identify
     the value when the form is submitted.

     - Parameters:
        - key: The key used to reference the value in the form.
        - value: The value to be sent.
     */
    public init<Key: StringProtocol, Value: LosslessStringConvertible>(
        key: Key,
        value: Value
    ) {
        self.key = String(key)
        self.value = String(value)
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension FormValue {

    /**
     Creates a new instance of `FormValue` to represent a value with a corresponding key in a form.

     The value parameter is the actual value to be sent, and key is the reference key used to identify
     the value when the form is submitted.

     - Parameters:
        - value: The value to be sent.
        - key: The key used to reference the value in the form.
     */
    @available(*, deprecated, message: "Prefers String init")
    public init(
        _ value: Any,
        forKey key: String
    ) {
        self.init(
            key: key,
            value: "\(value)"
        )
    }
}

extension FormValue {

    /// This method is used internally and should not be called directly.
        public static func _makeProperty(
        property: _GraphValue<FormValue>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(FormNode(inputs.environment.payloadPartLength) {
            PartFormRawValue(Data("\(property.value)".utf8), forHeaders: [
                kContentDisposition: kContentDispositionValue(
                    nil,
                    forKey: property.key
                )
            ])
        })
    }
}
