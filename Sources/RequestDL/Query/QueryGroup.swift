/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
A group of query parameters that can be used to compose a request.

You can use this to group multiple query parameters together and pass them as a single argument to a request.

Usage:

 ```swift
 QueryGroup {
     Query("John", forKey: "name")
     Query("Doe", forKey: "surname")
     Query(30, forKey: "age")
 }
 ```
 */
public struct QueryGroup<Content: Property>: Property {

    public typealias Body = Never

    let content: Content

    /**
     Creates a new query group from the content.

     - Parameter content: A closure that returns the content of the query group.
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
    ) async throws {
        let node = Node(
            root: context.root,
            object: EmptyObject(property),
            children: []
        )

        let newContext = Context(node)
        try await Content.makeProperty(property.content, newContext)

        let parameters = newContext.findCollection(Query.Object.self).map {
            ($0.key, $0.value)
        }

        context.append(Node(
            root: context.root,
            object: Object(parameters),
            children: []
        ))
    }
}

extension QueryGroup where Content == ForEach<[String: Any], Query> {

    public init(_ dictionary: [String: Any]) {
        self.init {
            ForEach(dictionary) {
                Query($0.value, forKey: $0.key)
            }
        }
    }
}

extension QueryGroup {

    struct Object: NodeObject {

        private let parameters: [(String, String)]

        init(_ parameters: [(String, String)]) {
            self.parameters = parameters
        }

        func makeProperty(_ make: Make) {
            guard
                let url = URL(string: make.request.url),
                var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            else { return }

            var queryItems = components.queryItems ?? []

            for (key, value) in parameters {
                queryItems.append(.init(name: key, value: value))
            }

            components.queryItems = queryItems

            make.request.url = (components.url ?? url).absoluteString
        }
    }
}
