/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct PropertyReader<Readable: Property, Content: Property>: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    let readable: Readable
    let content: @Sendable (PropertyContext) -> Content

    public init(
        _ readable: Readable,
        @PropertyBuilder _ content: @escaping @Sendable (PropertyContext) -> Content
    ) {
        self.readable = readable
        self.content = content
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<PropertyReader<Readable, Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let (read, make) = try await Resolve(
            root: property.readable,
            environment: inputs.environment
        ).partiallyBuild()

        let context = PropertyContext(make)
        let content = property.content(context)

        return try await _makeChildren(
            read: read,
            content: property.detach(next: content),
            inputs: inputs
        )
    }

    private static func _makeChildren(
        read: _PropertyOutputs,
        content: _GraphValue<Content>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        let content = try await Content._makeProperty(
            property: content,
            inputs: inputs
        )

        var children = ChildrenNode()

        children.append(read.node)
        children.append(content.node)

        return .children(children)
    }
}

public struct PropertyContext: Sendable {

    public var url: String {
        make.request.url
    }

    public var headers: HTTPHeaders {
        make.request.headers
    }

    private let make: Make

    init(_ make: Make) {
        self.make = make
    }
}
