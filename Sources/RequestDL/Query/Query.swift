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

    public typealias Body = Never

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

extension Query: PrimitiveProperty {

    class Object: NodeObject {

        let key: String
        let value: String

        init(_ value: Any, forKey key: String) {
            self.key = key
            self.value = "\(value)"
        }

        func makeProperty(_ make: Make) {
            guard
                let url = URL(string: make.request.url),
                var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            else { return }

            var queryItems = components.queryItems ?? []

            queryItems.append(.init(name: key, value: value))
            components.queryItems = queryItems

            make.request.url = (components.url ?? url).absoluteString
        }
    }

    func makeObject() -> Object {
        Object(value, forKey: key)
    }
}
