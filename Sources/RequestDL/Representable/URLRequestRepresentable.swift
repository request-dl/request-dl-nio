/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type that represents an object that can update a URLRequest.

 You can conform to this protocol to add or modify headers, set HTTP methods, and provide other customizations
 to the URLRequest for a network task.

 Usage:

 ```swift
 struct CustomHeader: URLRequestRepresentable {
     func updateRequest(_ request: inout URLRequest) {
         request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
     }
 }
 ```
 */
@available(*, deprecated)
public protocol URLRequestRepresentable: Property where Body == Never {

    /**
     Update the URLRequest to be used in a network task.

     - Parameter request: The `URLRequest` to be updated.
     */
    func updateRequest(_ request: inout URLRequest)
}

@available(*, deprecated)
extension URLRequestRepresentable {

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

@available(*, deprecated)
extension URLRequestRepresentable {

    private var pointer: Pointer<Self> {
        .init(self)
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Self>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        _ = inputs[self]
        return .init(Leaf(URLRequestRepresentableNode(
            property: property.pointer()
        )))
    }
}

@available(*, deprecated)
struct Pointer<Property> {

    private let pointer: Property

    init(_ pointer: Property) {
        self.pointer = pointer
    }

    func callAsFunction() -> Property {
        pointer
    }
}

@available(*, deprecated)
private struct URLRequestRepresentableNode<Property: URLRequestRepresentable>: PropertyNode {

    let property: Property

    func make(_ make: inout Make) async throws {
        property.updateRequest(&make.request)
    }
}
