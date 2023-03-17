/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 `Timeout` is a struct that defines the request timeout for a resource and request.

 Usage:

 To create an instance of `Timeout`, initialize it with the time interval and which source to be limited.

 ```swift
 Timeout(40, for: .request)
 ```

 In the example below, a request is made to Google's website with the timeout for all types.

 ```swift
 DataTask {
     BaseURL("google.com")
     Timeout(60, for: .all)
 }

 ```

 - Note: A request timeout is the amount of time a client will wait for a response from the server
 before terminating the connection. The timeout parameter is the duration of time before the timeout
 occurs, and the source parameter specifies the type of timeout to be applied
 */
public struct Timeout: Property {

    public typealias Body = Never

    let timeout: TimeInterval
    let source: Source

    /**
     Initializes a new instance of `Timeout`.

     - Parameters:
        - timeout: The duration of time before the timeout occurs.
        - source: The type of timeout to be applied.

     - Returns: A new instance of `Timeout`.

     - Note: By default, the `source` parameter is set to `.all`.

     */
    public init(_ timeout: TimeInterval, for source: Source = .all) {
        self.timeout = timeout
        self.source = source
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Timeout: PrimitiveProperty {

    struct Object: NodeObject {

        let timeout: TimeInterval
        let source: Source

        init(_ timeout: TimeInterval, _ source: Source) {
            self.timeout = timeout
            self.source = source
        }

        func makeProperty(_ make: Make) {
            if source.contains(.request) {
                make.configuration.timeout.connect = .seconds(Int64(timeout))
            }

            if source.contains(.resource) {
                make.configuration.timeout.read = .seconds(Int64(timeout))
            }
        }
    }

    func makeObject() -> Object {
        .init(timeout, source)
    }
}
