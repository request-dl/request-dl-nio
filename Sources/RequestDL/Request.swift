//
//  Request.swift
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
 The `Request` protocol is the foundation of all other objects in the RequestDL library.

 The protocol provides a `body` property, which returns an opaque `some Request` type.
 By combining multiple request objects, we can use the `body` property to configure
 multiple request properties at once. This is demonstrated in the following example:

 ```swift
 struct DefaultHeaders: Request {
    let cache: Bool

    var body: some Request {
        Headers.ContentType(.json)
        Headers.Accept(.json)

        if cache {
            Cache(.returnCacheDataElseLoad)
        }
    }
 }
 ```

 This `DefaultHeaders` struct conforms to the Request protocol and sets default
 headers for all requests. We can use many different objects to configure requests in
 order to meet specific application requirements.
 */
public protocol Request {

    associatedtype Body: Request

    /// An associated type that conforms to the Request protocol. This property
    /// allows you to set multiple request properties at once.
    @RequestBuilder
    var body: Body { get }

    /// This method is used internally and should not be called directly.
    static func makeRequest(_ request: Self, _ context: Context) async
}

extension Request {

    /// This method is used internally and should not be called directly.
    public static func makeRequest(_ request: Self, _ context: Context) async {
        let node = Node(
            root: context.root,
            object: EmptyObject(request),
            children: []
        )

        let newContext = context.append(node)
        await Body.makeRequest(request.body, newContext)
    }
}
