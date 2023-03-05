//
//  QueryGroup.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

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
        Never.bodyException()
    }

    /// This method is used internally and should not be called directly.
    public static func makeProperty(
        _ property: Self,
        _ context: Context
    ) async {
        let node = Node(
            root: context.root,
            object: EmptyObject(property),
            children: []
        )

        let newContext = Context(node)
        await Content.makeProperty(property.content, newContext)

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

        func makeProperty(_ configuration: MakeConfiguration) {
            guard
                let url = configuration.request.url,
                var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            else { return }

            var queryItems = components.queryItems ?? []

            for (key, value) in parameters {
                queryItems.append(.init(name: key, value: value))
            }

            components.queryItems = queryItems

            configuration.request.url = components.url ?? url
        }
    }
}
