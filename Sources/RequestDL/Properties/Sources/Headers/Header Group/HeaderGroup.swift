//
// See LICENSE for this package's licensing information.
//

/// A group of header properties that can be applied to a view.
///
/// Use a HeaderGroup to combine multiple header properties into a single property. The properties can be defined
/// either directly in the initializer or using a closure with a PropertyBuilder.
///
/// ```swift
/// HeaderGroup {
///     Headers.ContentType(.json)
///     CustomHeader("123", forKey: "key")
/// }
/// ```
public struct HeaderGroup<Content: Property>: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let content: Content

    // MARK: - Inits

    ///
    /// Initializes a new `HeaderGroup` with a closure that contains the header properties.
    ///
    /// - Parameter content: A closure that returns the `Content` containing the header properties.
    ///
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

        // Kept as individual `LeafNode<HeaderNode>` children rather than collapsed into one
        // opaque wrapper node: consumers that search the resolved graph for `HeaderNode`
        // directly — `Proxy`'s `connectHeaders`, `Form`'s per-part headers — need each header
        // to still be structurally discoverable. A single combined leaf hid them from that
        // search entirely, silently dropping every header composed through `HeaderGroup` in
        // those contexts.
        var children = ChildrenNode()

        for header in outputs.node.search(for: HeaderNode.self) {
            children.append(header)
        }

        return .children(children)
    }
}

extension HeaderGroup where Content == PropertyForEach<[String: String], String, CustomHeader> {

    ///
    /// Initializes a new `HeaderGroup` with a dictionary of headers.
    ///
    /// - Parameter dictionary: A dictionary containing header properties.
    ///
    public init(_ dictionary: [String: Any]) {
        let dictionary =
            (dictionary as? [String: String])
            ?? dictionary.mapValues {
                "\($0)"
            }

        self.init {
            PropertyForEach(dictionary, id: \.key) {
                CustomHeader(
                    name: $0.key,
                    value: $0.value
                )
            }
        }
    }
}
