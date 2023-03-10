/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A request that groups a set of requests together.

 You can use this request to group requests that share common properties, such as base URL or headers.

 Example:

 ```swift
 DataTask {
     BaseURL("api.example.com")

     Group {
         Path("users")
         Query(user.id, forKey: "id")
     }
 }
 ```
 */
public struct Group<Content: Property>: Property {

    private let content: Content

    /**
     Initializes the group request.

     - Parameters:
        - content: The closure that contains the requests to be grouped.
     */
    public init(@PropertyBuilder content: () -> Content) {
        self.content = content()
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
        await Content.makeProperty(property.content, context)
    }
}
