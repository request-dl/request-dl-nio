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
 }.request()
 ```
*/
public struct Query: Property {

    let key: String
    let value: Any

    /**
     Creates a new `Query` instance with a value and a key.

     - Parameters:
        - value: The value of the query parameter.
        - key: The key of the query parameter.
     */
    public init(_ value: Any, forKey key: String) {
        self.key = key
        self.value = "\(value)"
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Query {

    struct Node: PropertyNode {

        fileprivate let key: String
        fileprivate let value: String

        func make(_ make: inout Make) async throws {
            guard let url = URL(string: make.request.url) else {
                return
            }

            make.request.url = url.appendingQueries([.init(
                name: key,
                value: value
            )]).absoluteString
        }
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Query>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(Node(
            key: property.key,
            value: "\(property.value)"
        )))
    }
}
