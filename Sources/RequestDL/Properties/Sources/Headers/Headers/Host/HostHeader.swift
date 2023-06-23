/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A property that represents the host of a network request.
public struct HostHeader: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let value: String

    // MARK: - Inits

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

     - Parameter host: A `StringProtocol` representing the host.
     */
    public init<S: StringProtocol>(_ host: S) {
        self.value = String(host)
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<HostHeader>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(HeaderNode(
            key: "Host",
            value: property.value,
            strategy: inputs.environment.headerStrategy ?? .setting
        ))
    }
}
