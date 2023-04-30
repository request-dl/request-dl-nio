/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type that represents an asynchronous property specification.

 Usage example:

 ```swift
 DataTask {
     BaseURL("example.com")
     Path("api/users")
     RequestMethod(.get)

     AsyncProperty {
         if let id = try await getCurrentUserID() {
             Path("\(id)")
         }
     }
 }
 ```
 */
@RequestActor
public struct AsyncProperty<Content: Property>: Property {

    private let content: () async throws -> Content

    /**
     Initializes with an asynchronous content provided.

     - Parameters:
        - content: The content of the request to be built.
     */
    public init(@PropertyBuilder content: @RequestActor @escaping () async throws -> Content) {
        self.content = content
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }
}

extension AsyncProperty {

    /// This method is used internally and should not be called directly.
    @RequestActor
    public static func _makeProperty(
        property: _GraphValue<AsyncProperty<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let id = ObjectIdentifier(Content.self)
        let content = try await property.content()

        return try await Content._makeProperty(
            property: property.detach(id, next: content),
            inputs: inputs
        )
    }
}
