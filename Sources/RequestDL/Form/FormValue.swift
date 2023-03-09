/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// `FormValue` is a type of property that represents a single value in a multipart form-data request
///
/// It can be used to represent simple values like strings and numbers.
public struct FormValue: Property {

    public typealias Body = Never

    let key: String
    let value: Any

    /**
     Creates a new instance of `FormValue` to represent a value with a corresponding key in a form.

     The value parameter is the actual value to be sent, and key is the reference key used to identify
     the value when the form is submitted.

     - Parameters:
        - value: The value to be sent.
        - key: The key used to reference the value in the form.
     */
    public init(
        _ value: Any,
        forKey key: String
    ) {
        self.key = key
        self.value = value
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension FormValue: PrimitiveProperty {

    func makeObject() -> FormObject {
        FormObject {
            PartFormRawValue(Data("\(value)".utf8), forHeaders: [
                kContentDisposition: kContentDispositionValue(nil, forKey: key)
            ])
        }
    }
}
