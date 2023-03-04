//
//  ForEach.swift
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
 A request that iterates over a collection of data and creates a request for each element.

 You can use this request to dynamically generate requests based on a collection of data.

 Example:

 ```swift
 let paths = ["user", "search", "results"]

 DataTask {
     BaseURL("ecommerce.com")
     ForEach(paths) {
         Path($0)
     }
 }
 ```
 */
public struct ForEach<Data: Collection, Content: Request>: Request {

    private let data: Data
    private let map: (Data.Element) -> Content

    /**
     Initializes the `ForEach` request with collection of data provided.

     - Parameters:
         - data: The collection of data to iterate over.
         - content: A closure that creates a content for each element of the collection.
     */
    public init(
        _ data: Data,
        @RequestBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.map = content
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        Never.bodyException()
    }

    /// This method is used internally and should not be called directly.
    public static func makeRequest(_ request: ForEach<Data, Content>, _ context: Context) async {
        for request in request.data.map(request.map) {
            await Content.makeRequest(request, context)
        }
    }
}
