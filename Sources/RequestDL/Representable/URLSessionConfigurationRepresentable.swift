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

extension URLSessionConfigurationRepresentable {

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
            object: URLSessionRepresentableObject(property.updateSessionConfiguration(_:)),
            children: []
        )

        context.append(node)
    }
}

struct URLSessionRepresentableObject: NodeObject {

    private let update: (URLSessionConfiguration) -> Void

    init(_ update: @escaping (URLSessionConfiguration) -> Void) {
        self.update = update
    }

    func makeProperty(_ make: Make) {
        fatalError("Deprecated")
    }
}
