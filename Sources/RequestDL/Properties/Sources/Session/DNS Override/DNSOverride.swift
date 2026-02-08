/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 `DNSOverride` is a struct that allows overriding DNS resolution for a specific destination hostname with a custom IP address or hostname.

 This property is useful for testing, bypassing regional restrictions, or routing requests through specific servers by directly mapping a domain name to an IP address.

 ```swift
 DNSOverride("127.0.0.1", from: "example.com")
 ```

 In the example below, requests to "api.example.com" will be resolved to the IP address "10.0.0.1" instead of its standard DNS record.

 ```swift
 DataTask {
     BaseURL("api.example.com")
     DNSOverride("10.0.0.1", from: "api.example.com")
 }
 ```

 > Warning: Misusing DNS overrides can lead to connection errors or security risks if the custom origin is incorrect or untrusted. Ensure the override is intentional and correct.
 */
public struct DNSOverride: Property {

    private struct Node: PropertyNode {

        let origin: String
        let destination: String

        func make(_ make: inout Make) async throws {
            make.sessionConfiguration.dnsOverride[origin] = destination
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let origin: String
    let destination: String

    // MARK: - Inits

    /**
     Initializes a new instance of `DNSOverride`.

     This initializer maps a destination hostname to a specific origin address for DNS resolution.

     - Parameters:
        - destination: The custom IP address or hostname to which the `origin` will be resolved.
        - origin: The original hostname for which the DNS setting is to be overridden.

     > Note: The parameter order is `(_ destination, from origin)`, meaning the `origin` hostname will resolve to the `destination` address.
     */
    public init(_ destination: String, from origin: String) {
        self.origin = origin
        self.destination = destination
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<DNSOverride>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(
            origin: property.origin,
            destination: property.destination
        ))
    }

}
