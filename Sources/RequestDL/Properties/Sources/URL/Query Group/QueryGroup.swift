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
     Query("John", forKey: "name")
     Query("Doe", forKey: "surname")
     Query(30, forKey: "age")
 }
 ```
 */
public struct QueryGroup<Content: Property>: Property {

    let content: Content

    /**
     Creates a new query group from the content.

     - Parameter content: A closure that returns the content of the query group.
     */
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension QueryGroup where Content == ForEach<[String: Any], String, Query> {

    public init(_ dictionary: [String: Any]) {
        self.init {
            ForEach(dictionary, id: \.key) {
                Query($0.value, forKey: $0.key)
            }
        }
    }
}

extension QueryGroup {

    struct Node: PropertyNode {

        let leafs: [Leaf<Query.Node>]

        fileprivate init(_ leafs: [Leaf<Query.Node>]) {
            self.leafs = leafs
        }

        func make(_ make: inout Make) async throws {
            for leaf in leafs {
                try await leaf.make(&make)
            }
        }
    }

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

        return .init(Leaf(Node(output.node.search(for: Query.Node.self))))
    }
}
