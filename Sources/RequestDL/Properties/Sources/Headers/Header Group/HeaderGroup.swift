/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A group of header properties that can be applied to a view.

 Use a HeaderGroup to combine multiple header properties into a single property. The properties can be defined
 either directly in the initializer or using a closure with a PropertyBuilder.

 Example:

 ```swift
 HeaderGroup {
     Headers.ContentType(.json)
     Headers.Any("123", forKey: "key")
 }
 ```
 */
public struct HeaderGroup<Content: Property>: Property {

    private struct Node: PropertyNode {

        let nodes: [LeafNode<Headers.Node>]

        func make(_ make: inout Make) async throws {
            for node in nodes {
                try await node.make(&make)
            }
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let content: Content

    // MARK: - Inits

    /**
     Initializes a new `HeaderGroup` with a closure that contains the header properties.

     - Parameter content: A closure that returns the `Content` containing the header properties.
     */
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<HeaderGroup<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let outputs = try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )

        return .leaf(Node(nodes: outputs.node.search(for: Headers.Node.self)))
    }
}

extension HeaderGroup where Content == ForEach<[String: Any], String, Headers.`Any`> {

    /**
     Initializes a new `HeaderGroup` with a dictionary of headers.

     - Parameter dictionary: A dictionary containing header properties.
     */
    public init(_ dictionary: [String: Any]) {
        self.init {
            ForEach(dictionary, id: \.key) {
                Headers.Any(
                    name: $0.key,
                    value: "\($0.value)"
                )
            }
        }
    }
}
