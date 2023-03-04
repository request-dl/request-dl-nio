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

struct FormObject: NodeObject {

    let type: FormType

    init(_ type: FormType) {
        self.type = type
    }

    func makeRequest(_ configuration: RequestConfiguration) {
        let boundary = FormUtils.boundary
        configuration.request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        configuration.request.httpBody = FormUtils.buildBody([type.data], with: boundary)
    }
}

public struct Form<Content: Request>: Request {

    public typealias Body = Never

    let parameter: Content

    public init(@RequestBuilder parameter: () -> Content) {
        self.parameter = parameter()
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        Never.bodyException()
    }

    /// This method is used internally and should not be called directly.
    public static func makeRequest(_ request: Form<Content>, _ context: Context) async {
        let node = Node(
            root: context.root,
            object: EmptyObject(request),
            children: []
        )

        let newContext = Context(node)
        await Content.makeRequest(request.parameter, newContext)

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

        func makeRequest(_ configuration: RequestConfiguration) {
            let boundary = FormUtils.boundary
            configuration.request.setValue(
                "multipart/form-data; boundary=\(boundary)",
                forHTTPHeaderField: "Content-Type"
            )
            configuration.request.httpBody = FormUtils.buildBody(types.map(\.data), with: boundary)
        }
    }
}
