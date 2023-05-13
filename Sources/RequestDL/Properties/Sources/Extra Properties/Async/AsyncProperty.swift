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
public struct AsyncProperty<Content: Property>: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let content: @Sendable () async throws -> Content

    // MARK: - Inits

    /**
     Initializes with an asynchronous content provided.

     - Parameters:
        - content: The content of the request to be built.
     */
    public init(@PropertyBuilder content: @escaping @Sendable () async throws -> Content) {
        self.content = content
    }

    // MARK: - Static public methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<AsyncProperty<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()

        let content = try await property.content()

        return try await Content._makeProperty(
            property: property.detach(next: content),
            inputs: inputs
        )
    }
}
