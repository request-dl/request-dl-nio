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
 The Request protocol is the basis of all other objects, with it we have the body property
 that uses the opaque `some Request` return type. In this case, we can create new
 objects by combining the use of others to configure several properties of a request at once.

     import RequestDL

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

 We can explore and use many different objects to meet some application business
 rule. An example where this approach is interesting is in the case of tokens that
 are stored in some data provider and we have to pass the request to have access
 to a certain feature of the backend API.
 */
public protocol Request {

    /// The Request type representing the request body.
    associatedtype Body: Request

    /**
     Defines the properties of the request.

     When you implement a custom Request, you need to implement the body
     property to provide the request properties. Return a property by combining
     the Requests implemented by the RequestDL, as well as other Requests
     implemented by you.

         import RequestDL

         struct MyRequest: Request {

             var body: some Request {
                 Url("https://google.com")
             }
         }
     */
    @RequestBuilder
    var body: Body { get }

    /// Internal method
    static func makeRequest(_ request: Self, _ context: Context) async
}

extension Request {

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
