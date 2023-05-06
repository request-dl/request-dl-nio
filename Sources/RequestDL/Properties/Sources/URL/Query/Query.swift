/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A Property protocol conforming type that represents a query parameter in a URL request.

 You can use it to build a URLRequest with query parameters.

 Usage:

 ```swift
 try await DataTask {
     BaseURL("api.example.com")
     Path("users")
     Query("john@example.com", forKey: "email")
     Query(30, forKey: "age")
 }
 .result()
 ```
*/
@RequestActor
public struct Query<Value>: Property {

    let key: String
    let value: Value

    /**
     Creates a new `Query` instance with a value and a key.

     - Parameters:
        - value: The value of the query parameter.
        - key: The key of the query parameter.
     */
    public init(_ value: Value, forKey key: String) {
        self.key = key
        self.value = value
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Query {

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<Query>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(QueryNode(
            name: property.key,
            value: property.value,
            urlEncoder: inputs.environment.urlEncoder
        ))
    }
}
