//
//  Form.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
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
A type representing an HTTP form with a list of content.

Use Form to represent an HTTP form with a list of content, which can be used in an HTTP request. This type conforms to Property, allowing it to be composed with other Property objects.

The content of the form is specified using a property builder syntax, allowing you to create a list of Parameter objects.

 ```swift
 Form {
     FormValue("John", forKey: "name")
     FormValue(25, forKey: "age")
 }
 ```
 */
public struct Form<Content: Property>: Property {

    public typealias Body = Never

    let content: Content

    /**
     Initializes a new instance of `Form` with the specified list of properties.

     - Parameters:
        - content: A property builder closure that creates a list of `Property` objects.
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

        let parameters = newContext
            .findCollection(FormObject.self)
            .map(\.type)

        context.append(Node(
            root: context.root,
            object: Object(parameters),
            children: []
        ))
    }
}

extension Form {

    struct Object: NodeObject {
        private let types: [FormType]

        init(_ types: [FormType]) {
            self.types = types
        }

        func makeProperty(_ configuration: MakeConfiguration) {
            let boundary = FormUtils.boundary
            configuration.request.setValue(
                "multipart/form-data; boundary=\(boundary)",
                forHTTPHeaderField: "Content-Type"
            )
            configuration.request.httpBody = FormUtils.buildBody(types.map(\.data), with: boundary)
        }
    }
}
