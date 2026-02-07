/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The `Endpoint` defines the complete URL or relative path for a request, combining base URL, path components, and query parameters.

 ## Overview

 The `Endpoint` can be used in several ways:

 - **Complete URL**: Specify a full URL including scheme, host, and optional path/query components.
 - **Relative Path**: Provide just the path and query components to be appended to a configured base URL.
 - **Base URL Override**: When a complete URL is provided, it can override the existing base URL configuration.

 ```swift
 // Complete URL (overrides any configured BaseURL)
 Endpoint("https://api.example.com/v1/users?id=123")

 // Relative path (uses configured BaseURL)
 Endpoint("/users")
 Endpoint("/users/123")
 Endpoint("?search=term&page=1")
 ```

 > Important: When specifying a complete URL within the `Endpoint`, if it includes path components, RequestDL will prepend these paths from the beginning, potentially overriding existing path components configured elsewhere.

 > Note: If no scheme is provided in a complete URL, `https` is assumed by default.

 ### Supported Formats

 The `Endpoint` accepts:
 - Base URLs (`scheme://host:port`)
 - Path components (`path/to/resource`)
 - Query parameters (`?key=value&another=param`)

 You can combine these elements in a single string.

 ### Learn the fundamentals

 @Links(visualStyle: list) {
     - <doc:Defining-endpoints>
     - <doc:URL-composition>
 }
 */
public struct Endpoint: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let endpoint: String

    // MARK: - Init

    /**
     Creates an Endpoint from a string representation.

     The input can be:
     - A complete URL: "https://example.com/path?query=value"
     - A relative path: "/path/to/resource"
     - Query parameters only: "?key=value"

     - Parameter endpoint: The URL string defining the endpoint.
     */
    public init<S: StringProtocol>(_ endpoint: S) {
        self.endpoint = String(endpoint)
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Endpoint>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(EndpointNode(endpoint: property.endpoint))
    }
}
