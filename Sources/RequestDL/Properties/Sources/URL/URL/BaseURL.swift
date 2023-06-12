/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The BaseURL struct defines the base URL for a request. It provides the
 internet protocol and the host for the request.

 To create a BaseURL object, you need to provide the internet protocol
 and the string host. You can also set the internet protocol to HTTPS by
 default if you only provide the host.

 Example usage:

 ```swift
 import RequestDL

 struct AppleDeveloperBaseURL: Property {
     var body: some Property {
         BaseURL(.https, host: "developer.apple.com")
     }
 }

 ```

 Or you can set the host without specifying the protocol type:

 ```swift
 struct AppleDeveloperBaseURL: Property {
     var body: some Property {
         BaseURL("developer.apple.com")
     }
 }
 ```
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

    // MARK: - Private properties

    private var absoluteString: String {
        if host.contains("://") {
            Internals.Log.failure(
                .invalidHost(host)
            )
        }

        guard let host = host.split(separator: "/").first else {
            Internals.Log.failure(
                .unexpectedHost(host)
            )
        }

        return "\(scheme.rawValue)://\(host)"
    }

    // MARK: - Init

    /**
     Creates a BaseURL by combining the internet protocol and the string host.

     - Parameters:
        - scheme: The internet protocol chosen.
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
     Defines the base URL from the host with the default HTTPS protocol.

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
        return .leaf(Node(baseURL: property.absoluteString))
    }
}
