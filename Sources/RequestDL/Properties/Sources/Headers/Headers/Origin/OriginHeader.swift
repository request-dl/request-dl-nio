/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A representation of the `OriginHeader` header field in an HTTP message.

 The `OriginHeader` header field indicates the origin of the request in terms of scheme,
 host, and port number. This header is mainly used in the context of CORS (Cross-Origin
 Resource Sharing) requests to ensure that a web application can only access resources
 from a different origin if the server explicitly allows it.

 Example usage:

 ```swift
 OriginHeader("https://example.com")
 ```
 */
public struct OriginHeader: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let value: String

    // MARK: - Inits

    /**
     Initializes a `OriginHeader` property with the given `host` and `port`.

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
     Initializes an `OriginHeader` header field with the given origin value.

     - Parameter host: A `StringProtocol` representing the host.
     */
    public init<S: StringProtocol>(_ origin: S) {
        self.value = String(origin)
    }

    // MARK: - Static public methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<OriginHeader>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(HeaderNode(
            key: "Origin",
            value: property.value,
            strategy: inputs.environment.headerStrategy
        ))
    }
}

@available(*, deprecated)
extension Headers {

    @available(*, deprecated, renamed: "OriginHeader")
    public typealias Origin = OriginHeader
}
