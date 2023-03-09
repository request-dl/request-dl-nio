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
         if let id = await getCurrentUserID() {
             Path("\(id)")
         }
     }
 }
 ```
 */
public struct AsyncProperty<Content: Property>: Property {

    public typealias Body = Never

    private let content: () async -> Content

    /**
     Initializes with an asynchronous content provided.

     - Parameters:
        - content: The content of the request to be built.
     */
    public init(@PropertyBuilder content: @escaping () async -> Content) {
        self.content = content
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    /// This method is used internally and should not be called directly.
    public static func makeProperty(
        _ property: Self,
        _ context: Context
    ) async {
        await Content.makeProperty(property.content(), context)
    }
}
