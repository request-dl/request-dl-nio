//
//  Path.swift
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
 Use Path to specify the URL pathway.

 You can have multiple Paths inside the body or @RequestBuilder results,
 which will be combined in to a single Path appended at BaseURL.

 ```swift
 struct AppleDeveloperDefaultPaths: Request {

     var body: some Request {
         Path("api/v2/ios")
     }
 }
 ```

 Or multiple Paths:

 ```swift
 struct AppleDeveloperDefaultPaths: Request {

     var body: some Request {
         Path("api")
         Path("v2")
         Path("ios")
     }
 }
 ```
 */
public struct Path: Request {

    public typealias Body = Never

    private let path: String

    /**
     Instantiate the Path with a string.

     - Parameters:
        - path: The string path.
     */
    public init(_ path: String) {
        self.path = path
    }

    public var body: Never {
        Never.bodyException()
    }
}

extension Path: PrimitiveRequest {

    struct Object: NodeObject {

        let path: String

        init(_ path: String) {
            self.path = path
        }

        func makeRequest(_ configuration: RequestConfiguration) {
            guard let url = configuration.request.url else {
                return
            }

            configuration.request.url = url.appendingPathComponent(path)
        }
    }

    func makeObject() -> Object {
        .init(
            path
                .split(separator: "/")
                .filter { !$0.isEmpty }
                .joined(separator: "/")
        )
    }
}
