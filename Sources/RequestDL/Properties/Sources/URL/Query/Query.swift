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
     Query(name: "email", value: "john@example.com")
     Query(name: "age", value: 30)
 }
 .result()
 ```
*/
public struct Query<Value: Sendable>: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let name: String
    let value: Value

    // MARK: - Inits

    /**
     Creates a new `Query` instance with a name and value.

     - Parameters:
        - name: The name of the query parameter.
        - value: The value of the query parameter.
     */
    public init<Name: StringProtocol>(name: Name, value: Value) {
        self.name = String(name)
        self.value = value
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Query>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(QueryNode(
            name: property.name,
            value: property.value,
            urlEncoder: inputs.environment.urlEncoder
        ))
    }
}
