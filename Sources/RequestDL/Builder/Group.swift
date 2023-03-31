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
}

extension Group {

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<Group<Content>>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        let output = try await Content._makeProperty(
            property: property.content,
            inputs: inputs[self, \.content]
        )

        var children = ChildrenNode()
        children.append(output.node)
        return .init(children)
    }
}
