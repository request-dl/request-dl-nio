//
//  Path.swift
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
 Use Path to specify the URL pathway.

 You can have multiple Paths inside the body or @PropertyBuilder results,
 which will be combined in to a single Path appended at BaseURL.

 Example of single path:

 ```swift
 struct AppleDeveloperDefaultPaths: Property {

     var body: some Property {
         Path("api/v2/ios")
     }
 }
 ```

 Example of multiple paths:

 ```swift
 struct AppleDeveloperDefaultPaths: Property {

     var body: some Property {
         Path("api")
         Path("v2")
         Path("ios")
     }
 }
 ```

 The resulting URL from multiple paths is the concatenation of all paths,
 appended at the BaseURL. If any path has a leading or trailing slash, it will
 be trimmed. If you want to include a slash as a part of the path, you can
 escape it using a backslash (\\).

 ```swift
 struct ExampleRequest: Property {

     var body: some Property {
         Path("users")
         Path("1234")
         Path("\\/posts")
     }
 }

 The resulting URL of the above request would be `BaseURL/users/1234\/posts`.
 ```
 */
public struct Path: Property {

    public typealias Body = Never

    private let path: String

    /**
     Instantiate the Path with a string.

     - Parameters:
        - path: The string path. Any leading or trailing slashes will be trimmed.
        If you want to include a slash as a part of the path, escape it using a backslash (\\).
     */
    public init(_ path: String) {
        self.path = path
    }

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        Never.bodyException()
    }
}

extension Path: PrimitiveProperty {

    struct Object: NodeObject {

        let path: String

        init(_ path: String) {
            self.path = path
        }

        func makeProperty(_ configuration: MakeConfiguration) {
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
