/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Headers {

    /**
     A representation of the `Origin` header field in an HTTP message.

     The `Origin` header field indicates the origin of the request in terms of scheme, host, and port
     number. This header is mainly used in the context of CORS (Cross-Origin Resource Sharing)
     requests to ensure that a web application can only access resources from a different origin if the server
     explicitly allows it.

     Example usage:

     ```swift
     Headers.Origin("https://example.com")
     ```
     */
    @RequestActor
    public struct Origin: Property {

        private let value: String

        /**
         Initializes a `Origin` property with the given `host` and `port`.

         - Parameters:
            - host: A `StringProtocol` representing the host.
            - port: A `StringProtocol` representing the port.
         */
        public init<Host, Port>(
            _ host: Host,
            port: Port
        ) where Host: StringProtocol, Port: StringProtocol {
            self.value = "\(host):\(port)"
        }

        /**
         Initializes an `Origin` header field with the given origin value.

         - Parameter host: A `StringProtocol` representing the host.
         */
        public init<S: StringProtocol>(_ origin: S) {
            self.value = String(origin)
        }

        /// Returns an exception since `Never` is a type that can never be constructed.
        public var body: Never {
            bodyException()
        }
    }
}

extension Headers.Origin {

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<Headers.Origin>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Headers.Node(
            key: "Origin",
            value: property.value
        ))
    }
}
