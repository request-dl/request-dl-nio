/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A property that groups together other properties for use in a `DataTask`.
///
/// A `Group` property is used to group together other properties that share common characteristics, such
/// as a base URL or query parameters. In the example code below, a `Group` property is used
/// to group a `Path` property and a `Query` that specify the endpoint and a user ID for a request to
/// the "api.example.com" server.
///
/// ```swift
/// DataTask {
///     BaseURL("api.example.com")
///
///     Group {
///         Path("users")
///         Query(user.id, forKey: "id")
///     }
/// }
/// ```
public struct Group<Content: Property>: Property {

    /// The properties contained within the group.
    public let content: Content

    /// Creates a new `Group` property with the specified properties.
    ///
    /// - Parameter content: The properties to be contained within the group.
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension Group {

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Group<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertIfNeeded()

        let output = try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )

        var children = ChildrenNode()
        children.append(output.node)
        return .init(children)
    }
}
