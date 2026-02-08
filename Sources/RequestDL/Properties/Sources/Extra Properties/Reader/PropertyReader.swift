/*
See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A property that reads data from a source property and provides it to a content closure.
 This type allows you to create a dependency between two properties, where the `source`
 property is resolved first, and its result is made available within the `content` closure
 via a `PropertyContext`.
 */
public struct PropertyReader<Source: Property, Content: Property>: Property {

    // MARK: - Public properties

    /// This property always throws an error because `Never` cannot be instantiated.
    /// It serves as a placeholder to satisfy the `Property` protocol requirement.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internals properties

    let source: Source
    let content: @Sendable (PropertyContext) -> Content

    // MARK: - Inits

    /**
     Initializes a new `PropertyReader`.

     - Parameters:
       - source: The property whose output will be made available to the `content` closure.
       - content: A closure that receives a `PropertyContext` and returns the main content property.
                  The context provides access to the resolved output of the `readable` property.
     */
    public init(
        _ source: Source,
        @PropertyBuilder _ content: @escaping @Sendable (PropertyContext) -> Content
    ) {
        self.source = source
        self.content = content
    }

    // MARK: - Public static methods

    /// This method is used internally by the framework to build the property graph.
    /// It should not be called directly by user code.
    public static func _makeProperty(
        property: _GraphValue<PropertyReader<Source, Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let (source, make) = try await Resolve(
            root: property.source,
            environment: inputs.environment
        ).partiallyBuild()

        let context = PropertyContext(make)
        let content = property.content(context)

        return try await _makeChildren(
            source: source,
            content: property.detach(next: content),
            inputs: inputs
        )
    }

    // MARK: - Private static methods

    private static func _makeChildren(
        source: _PropertyOutputs,
        content: _GraphValue<Content>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        let content = try await Content._makeProperty(
            property: content,
            inputs: inputs
        )

        var children = ChildrenNode()

        children.append(source.node)
        children.append(content.node)

        return .children(children)
    }
}
