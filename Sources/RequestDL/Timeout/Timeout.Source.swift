//
//  Timeout.Source.swift
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

extension Timeout {

    /**
     A set of options representing the types of timeout available for each request.

     Use the static properties of this struct to set the timeout interval for requests and resources.

     1. `request`: The timeout request case. The default value is 60s.
     2. `resource`: The timeout resources case. The default value is 7 days in seconds.
     3. `all`: Defines the same timeout interval for both request and resource.

     In the example below, a request is made to the Google's website with the timeout for all types.

     ```swift
     extension GoogleAPI {

         func website() -> DataTask {
             DataTask {
                 BaseURL("google.com")
                 Timeout(60, for: .all)
             }
         }
     }
     ```
     */
    public struct Source: OptionSet {

        /// The timeout interval for the request.
        public static let request = Source(rawValue: 1 << 0)

        /// The timeout interval for resource which determinate how long
        /// to wait the resource to be transferred.
        public static let resource = Source(rawValue: 1 << 1)

        /// Defines same timeout interval for `request` and `resource`
        public static let all: Self = [.request, .resource]

        public let rawValue: Int

        /**
         Initializes a new timeout source with the given raw value.

         - parameter rawValue: The raw value to use for the timeout source.
         */
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}
