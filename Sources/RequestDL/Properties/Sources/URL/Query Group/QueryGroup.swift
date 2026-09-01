//
// See LICENSE for this package's licensing information.
//

/// A group of query parameters that can be used to compose a request.
///
/// You can use this to group multiple query parameters together and pass them as a single argument to a request.
///
///  ```swift
///  QueryGroup {
///      Query(name: "name", value: "John")
///      Query(name: "surname", value: "Doe")
///      Query(name: "age", value: 30)
///  }
///  ```
public struct QueryGroup<Content: Property>: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let content: Content

    // MARK: - Inits

    ///
    /// Creates a new query group from the content.
    ///
    /// - Parameter content: A closure that returns the content of the query group.
    ///
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

        // Kept as individual `LeafNode<QueryNode>` children rather than collapsed into one
        // opaque wrapper node: a `QueryGroup` nested inside another `QueryGroup` needs its own
        // resolved queries to still be structurally discoverable by the outer group's own
        // `search(for: QueryNode.self)`. A single combined leaf hid them from that search
        // entirely, silently dropping every query composed through a nested `QueryGroup` — the
        // same class of bug fixed for `HeaderGroup`, whose leaf-wrapping broke `Proxy`'s and
        // `Form`'s external searches for `HeaderNode` the same way.
        var children = ChildrenNode()

        for query in output.node.search(for: QueryNode.self) {
            children.append(query)
        }

        return .children(children)
    }
}

extension QueryGroup where Content == PropertyForEach<[String: Sendable], String, Query<Sendable>> {

    public init(_ dictionary: [String: Sendable]) {
        self.init {
            PropertyForEach(dictionary, id: \.key) {
                Query(name: $0.key, value: $0.value)
            }
        }
    }
}
