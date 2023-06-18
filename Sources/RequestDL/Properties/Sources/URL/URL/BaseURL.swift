/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The `BaseURL` is the entry point as it specifies the scheme and host to be queried during the request.

 ## Overview

 To start using it, it is important to pay attention to some rules:

 - Scheme must be of type ``RequestDL/URLScheme``.
 - Host is a string without scheme.

 Here's an example of usage:

 ```swift
 // Always HTTPS
 BaseURL("apple.com")

 // Specifying the scheme
 BaseURL(.http, host: "apple.com")
 ```

 - Note: Successively specifying the `BaseURL` within a declarative block will override the previously specified value.

 - Warning: It is extremely important to specify the BaseURL in each request. Otherwise, RequestDL may throw an error.

 ## See Also

 - <doc:Creating-requests-from-scratch>
 - <doc:Cache-support>
 */
public struct BaseURL: Property {

    private struct Node: PropertyNode {

        let baseURL: String

        func make(_ make: inout Make) async throws {
            make.request.baseURL = baseURL
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let scheme: URLScheme
    let host: String

    // MARK: - Init

    /**
     Creates a BaseURL by combining the url scheme and the string host.

     - Parameters:
        - scheme: The url scheme chosen.
        - path: The string host only.

     Example usage:

     ```swift
     import RequestDL

     struct AppleDeveloperBaseURL: Property {

         var body: some Property {
             BaseURL(.https, host: "developer.apple.com")
         }
     }
     ```
     */
    public init(_ scheme: URLScheme, host: String) {
        self.scheme = scheme
        self.host = host
    }

    /**
     Defines the base URL from the host with the default HTTPS scheme.

     - Parameters:
        - path: The string host only.

     Example usage:

     ```swift
     import RequestDL

     struct AppleDeveloperBaseURL: Property {

         var body: some Property {
             BaseURL("developer.apple.com")
         }
     }
     ```
     */
    public init(_ host: String) {
        self.init(.https, host: host)
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<BaseURL>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return try .leaf(Node(baseURL: property.pointer().path()))
    }

    // MARK: - Private methods

    private func path() throws -> String {
        if host.contains("://") {
            throw BaseURLError(
                context: .invalidHost,
                baseURL: host
            )
        }

        guard let host = host.split(separator: "/").first else {
            throw BaseURLError(
                context: .unexpectedHost,
                baseURL: host
            )
        }

        return "\(scheme.rawValue)://\(host)"
    }
}
