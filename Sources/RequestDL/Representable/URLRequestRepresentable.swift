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

extension URLRequestRepresentable {

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    /// This method is used internally and should not be called directly.
    public static func makeProperty(
        _ property: Self,
        _ context: Context
    ) async {
        let node = Node(
            root: context.root,
            object: URLRequestRepresentableObject(property.updateRequest(_:)),
            children: []
        )

        context.append(node)
    }
}

struct URLRequestRepresentableObject: NodeObject {

    private let update: (inout URLRequest) -> Void

    init(_ update: @escaping (inout URLRequest) -> Void) {
        self.update = update
    }

    func makeProperty(_ make: Make) {
        fatalError("Deprecated")
    }
}
