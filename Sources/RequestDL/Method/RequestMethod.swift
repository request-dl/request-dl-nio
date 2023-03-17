/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 Defines the HTTP request method.

 Use `RequestMethod` to specify the HTTP request method when creating requests.

 ```swift
 DataTask {
     BaseURL("ecommerce.com")
     Path("products")
     RequestMethod(.get)
 }
 ```
 */
public struct RequestMethod: Property {

    public typealias Body = Never

    let httpMethod: HTTPMethod

    /**
     Initializes a `RequestMethod` instance with the specified HTTP request method.

     - Parameter httpMethod: The HTTP request method to use.

     In the following example, a GET request is made to the Apple developers website:

     ```swift
     DataTask {
         BaseURL("developer.apple.com")
         RequestMethod(.get)
     }
     */
    public init(_ httpMethod: HTTPMethod) {
        self.httpMethod = httpMethod
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension RequestMethod: PrimitiveProperty {

    struct Object: NodeObject {

        private let httpMethod: String

        init(_ httpMethod: String) {
            self.httpMethod = httpMethod
        }

        func makeProperty(_ make: Make) {
            make.request.method = .init(httpMethod)
        }
    }

    func makeObject() -> Object {
        .init(httpMethod.rawValue)
    }
}
