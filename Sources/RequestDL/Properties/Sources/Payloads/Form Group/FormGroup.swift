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
     Form(
         name: "name",
         verbatim: "John"
     )

     Form(
         name: "age",
         verbatim: "25"
     )
 }
 ```
 */
public struct FormGroup<Content: Property>: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let content: Content

    // MARK: - Inits

    /**
     Initializes a new instance of `Form` with the specified list of properties.

     - Parameters:
        - content: A property builder closure that creates a list of `Property` objects.
     */
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<FormGroup<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let outputs = try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )

        let nodes = outputs.node.search(for: FormNode.self)

        return .leaf(FormNode(
            chunkSize: inputs.environment.payloadChunkSize,
            items: nodes.lazy.map(\.items).reduce([], +)
        ))
    }
}
