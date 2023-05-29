/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
A group of query parameters that can be used to compose a request.

You can use this to group multiple query parameters together and pass them as a single argument to a request.

Usage:

 ```swift
 QueryGroup {
     Query(name: "name", value: "John")
     Query(name: "surname", value: "Doe")
     Query(name: "age", value: 30)
 }
 ```
 */
public struct QueryGroup<Content: Property>: Property {

    struct Node: PropertyNode {

        let leafs: [LeafNode<QueryNode>]

        fileprivate init(_ leafs: [LeafNode<QueryNode>]) {
            self.leafs = leafs
        }

        func make(_ make: inout Make) async throws {
            for leaf in leafs {
                try await leaf.make(&make)
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
     Creates a new query group from the content.

     - Parameter content: A closure that returns the content of the query group.
     */
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<QueryGroup<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let output = try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )

        return .leaf(Node(output.node.search(for: QueryNode.self)))
    }
}

extension QueryGroup where Content == ForEach<[String: Any], String, Query<Any>> {

    public init(_ dictionary: [String: Any]) {
        self.init {
            ForEach(dictionary, id: \.key) {
                Query(name: $0.key, value: $0.value)
            }
        }
    }
}
