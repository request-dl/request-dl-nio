/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type representing an HTTP form with a list of content.

 Use `FormGroup` to represent an HTTP form with a list of content, which can be used in an HTTP request.
 This type conforms to `Property`, allowing it to be composed with other `Property` objects.

 The content of the form is specified using a property builder syntax, allowing you to create a list of
 properties objects.

 ```swift
 FormGroup {
     FormValue("John", forKey: "name")
     FormValue(25, forKey: "age")
 }
 ```
 */
public struct FormGroup<Content: Property>: Property {

    let content: Content

    /**
     Initializes a new instance of `Form` with the specified list of properties.

     - Parameters:
     - content: A property builder closure that creates a list of `Property` objects.
     */
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension FormGroup {

    private struct Node: PropertyNode {

        let nodes: [Leaf<FormNode>]

        func make(_ make: inout Make) async throws {
            let multipart = nodes.map(\.factory).map { $0() }

            let constructor = MultipartFormConstructor(multipart)

            make.request.headers.setValue(
                "multipart/form-data; boundary=\"\(constructor.boundary)\"",
                forKey: "Content-Type"
            )

            make.request.body = Internals.RequestBody {
                Internals.BodyItem(constructor.body)
            }
        }
    }

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<FormGroup<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        let inputs = inputs[self, \.content]

        let outputs = try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )

        let nodes = outputs.node.search(for: FormNode.self)

        return .init(Leaf(Node(nodes: nodes)))
    }
}
