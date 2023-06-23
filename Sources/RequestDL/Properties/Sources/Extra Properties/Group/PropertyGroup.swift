/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A property that groups together other properties for use in a ``RequestTask``.

 A ``PropertyGroup`` property is used to group together other properties that share common characteristics,
 such as a base URL or query parameters.

 In the example code below, a ``PropertyGroup`` property is used to group a ``Path`` property and a
 ``Query`` that specify the endpoint and a user ID for a request to the "api.example.com" server.

 ```swift
 DataTask {
     BaseURL("api.example.com")

     PropertyGroup {
         Path("users")
         Query(name: "id", value: user.id)
     }
 }
 ```
 */
public struct PropertyGroup<Content: Property>: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    /// The properties contained within the group.
    public let content: Content

    // MARK: - Inits

    /**
     Groups ``Property`` using ``PropertyBuilder`` result builder.

     - Parameter content: The properties to be grouped.
     */
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<PropertyGroup<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        return try await Content._makeProperty(
            property: property.content,
            inputs: inputs
        )
    }
}
