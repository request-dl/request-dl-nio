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

    private struct Node: PropertyNode {

        let httpMethod: String

        func make(_ make: inout Make) async throws {
            make.request.method = .init(httpMethod)
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let httpMethod: HTTPMethod

    // MARK: - Inits

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

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<RequestMethod>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(
            httpMethod: property.httpMethod.rawValue
        ))
    }
}
