//
//  Headers.Referer.swift
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

extension Headers {

    /**
     A header that specifies the URL of a resource from which the requested resource was obtained.

     Usage:

     ```swift
     Headers.Referer("https://www.example.com/")
     ```
     */
    public struct Referer: Property {

        private let value: Any

        /**
         Initialize the `Referer` header with a URL that specifies the resource from which
         the requested resource was obtained.

         - Parameter url: The URL of the resource.
         */
        public init<S: StringProtocol>(_ url: S) {
            self.value = url
        }

        /// Returns an exception since `Never` is a type that can never be constructed.
        public var body: Never {
            Never.bodyException()
        }
    }
}

extension Headers.Referer: PrimitiveProperty {

    func makeObject() -> Headers.Object {
        .init(value, forKey: "Referer")
    }
}
