/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The `FlexibleURL` defines the complete URL or relative path for a request, combining base URL, path components, and query parameters.

 ## Overview

 The `FlexibleURL` can be used in several ways:

 - **Complete URL**: Specify a full URL including scheme, host, and optional path/query components.
 - **Relative Path**: Provide just the path and query components to be appended to a configured base URL.
 - **Base URL Override**: When a complete URL is provided, it can override the existing base URL configuration.

 ```swift
 // Complete URL (overrides any configured BaseURL)
 FlexibleURL("https://api.example.com/v1/users?id=123")

 // Relative path (uses configured BaseURL)
 FlexibleURL("/users")
 FlexibleURL("/users/123")
 FlexibleURL("?search=term&page=1")
 ```

 > Important: When specifying a complete URL within the `FlexibleURL`, if it includes path components, RequestDL will prepend these paths from the beginning, potentially overriding existing path components configured elsewhere.

 > Note: If no scheme is provided in a complete URL, `https` is assumed by default.

 ### Supported Formats

 The `FlexibleURL` accepts:
 - Base URLs (`scheme://host:port`)
 - Path components (`path/to/resource`)
 - Query parameters (`?key=value&another=param`)

 You can combine these elements in a single string.
 */
public struct FlexibleURL: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let url: String

    // MARK: - Init

    /**
     Creates an FlexibleURL from a string representation.

     The input can be:
     - A complete URL: "https://example.com/path?query=value"
     - A relative path: "/path/to/resource"
     - Query parameters only: "?key=value"

     - Parameter url: The URL string.
     */
    public init<S: StringProtocol>(_ url: S) {
        self.url = String(url)
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<FlexibleURL>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(FlexibleURLNode(url: property.url))
    }
}
