/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 `Timeout` is a struct that defines the request timeout for a connect and read.

 Usage:

 To create an instance of `Timeout`, initialize it with the time interval and which source to be limited.

 ```swift
 Timeout(.seconds(40), for: .connect)
 ```

 In the example below, a request is made to Google's website with the timeout for all types.

 ```swift
 DataTask {
     BaseURL("google.com")
     Timeout(.seconds(60), for: .all)
 }

 ```

 - Note: A request timeout is the amount of time a client will wait for a response from the server
 before terminating the connection. The timeout parameter is the duration of time before the timeout
 occurs, and the source parameter specifies the type of timeout to be applied
 */
public struct Timeout: Property {

    let timeout: UnitTime
    let source: Source

    /**
     Initializes a new instance of `Timeout`.

     - Parameters:
        - timeout: The duration of time before the timeout occurs.
        - source: The type of timeout to be applied.

     - Returns: A new instance of `Timeout`.

     - Note: By default, the `source` parameter is set to `.all`.

     */
    public init(_ timeout: UnitTime, for source: Source = .all) {
        self.timeout = timeout
        self.source = source
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Timeout {

    private struct Node: PropertyNode {

        let timeout: UnitTime
        let source: Source

        func make(_ make: inout Make) async throws {
            if source.contains(.connect) {
                make.configuration.timeout.connect = timeout
            }

            if source.contains(.read) {
                make.configuration.timeout.read = timeout
            }
        }
    }

    /// This method is used internally and should not be called directly.
        public static func _makeProperty(
        property: _GraphValue<Timeout>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(Node(
            timeout: property.timeout,
            source: property.source
        ))
    }
}
