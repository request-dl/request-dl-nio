/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Headers {

    /// A property that represents the host of a network request.
    public struct Host: Property {

        private let value: Any

        /**
         Initializes a `Host` property with the given `host` and `port`.

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
         Initializes a `Host` property with the given `host`.

         - Parameters:
            - host: A `StringProtocol` representing the host.
         */
        public init<S: StringProtocol>(_ host: S) {
            self.value = host
        }

        /// Returns an exception since `Never` is a type that can never be constructed.
        public var body: Never {
            bodyException()
        }
    }
}

extension Headers.Host {

    public static func _makeProperty(
        property: _GraphValue<Headers.Host>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(Headers.Node(
            property.value,
            forKey: "Host"
        )))
    }
}
