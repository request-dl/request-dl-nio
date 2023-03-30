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

    public typealias Body = Never

    let internetProtocol: InternetProtocol
    let host: String

    /**
     Creates a BaseURL by combining the internet protocol and the string host.

     - Parameters:
        - internetProtocol: The internet protocol chosen.
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
    public init(_ internetProtocol: InternetProtocol, host: String) {
        self.internetProtocol = internetProtocol
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

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension BaseURL {

    fileprivate var absoluteString: String {
        if host.contains("://") {
            Internals.Log.failure(
                """
                Invalid host string: The protocol communication should \
                not be included.
                """
            )
        }

        guard let host = host.split(separator: "/").first else {
            Internals.Log.failure(
                """
                Unexpected format for host string: Could not extract the \
                host.
                """
            )
        }

        return "\(internetProtocol.rawValue)://\(host)"
    }
}

extension BaseURL {

    struct Node: PropertyNode {

        let baseURL: URL

        fileprivate init(_ baseURL: URL) {
            self.baseURL = baseURL
        }

        func make(_ make: inout Make) async throws {}
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<BaseURL>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]

        guard let baseURL = URL(string: property.absoluteString) else {
            Internals.Log.failure(
                """
                Failed to create URL from absolute string: \
                \(property.absoluteString)
                """
            )
        }

        return .init(Leaf(Node(baseURL)))
    }
}
