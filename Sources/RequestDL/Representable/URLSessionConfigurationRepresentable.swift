/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type that can be represented as a `URLSessionConfiguration`.

 Types that conform to the `URLSessionConfigurationRepresentable` protocol can update a `URLSessionConfiguration`
 object with specific attributes.

 To adopt this protocol, implement the `updateSessionConfiguration` method, which updates the session configuration
 object passed in as an argument.

 ```swift
 struct MySessionConfiguration: URLSessionConfigurationRepresentable {

     let timeoutIntervalForRequest: TimeInterval

     func updateSessionConfiguration(_ sessionConfiguration: URLSessionConfiguration) {
         sessionConfiguration.timeoutIntervalForRequest = timeoutIntervalForRequest
     }
 }
 ```
 */
@available(*, deprecated)
public protocol URLSessionConfigurationRepresentable: Property where Body == Never {

    /**
     Updates the session configuration object with specific attributes.

     - Parameter sessionConfiguration: The `URLSessionConfiguration` object to be updated.
     */
    func updateSessionConfiguration(_ sessionConfiguration: URLSessionConfiguration)
}

@available(*, deprecated)
extension URLSessionConfigurationRepresentable {

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

@available(*, deprecated)
extension URLSessionConfigurationRepresentable {

    private var pointer: Pointer<Self> {
        .init(self)
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Self>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(URLSessionConfigurationRepresentableNode(
            property: property.pointer()
        )))
    }
}

@available(*, deprecated)
private struct URLSessionConfigurationRepresentableNode<Property: URLSessionConfigurationRepresentable>: PropertyNode {

    let property: Property

    func make(_ make: inout Make) async throws {
        property.updateSessionConfiguration(make.configuration)
    }
}
