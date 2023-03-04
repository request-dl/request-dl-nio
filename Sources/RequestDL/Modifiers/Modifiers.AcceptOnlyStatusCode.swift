//
//  Modifiers.StatusCode.swift
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

extension Modifiers {

    /// A modifier that accepts only a specific set of status codes as a successful response.
    public struct AcceptOnlyStatusCode<Content: Task>: TaskModifier where Content.Element: TaskResultPrimitive {

        private let statusCodes: StatusCodeSet

        init(_ statusCodes: StatusCodeSet) {
            self.statusCodes = statusCodes
        }

        /**
         Modifies a task to accept only the specified status codes.

         - Parameter task: The task to modify.
         - Returns: The modified task that accepts only the specified status codes.
         - Throws: An `InvalidStatusCodeError` if the status code of the response is not included in the set of accepted status codes.
         */
        public func task(_ task: Content) async throws -> Content.Element {
            let result = try await task.response()

            guard
                let httpResponse = result.response as? HTTPURLResponse,
                statusCodes.isEmpty || statusCodes.contains(.custom(httpResponse.statusCode))
            else {
                throw InvalidStatusCodeError<Content.Element>(data: result)
            }

            return result
        }
    }
}

extension Task where Element: TaskResultPrimitive {

    /**
     Returns a modified task that accepts only the specified status codes.

     - Parameter statusCodes: The set of status codes to accept.
     - Returns: A modified task that accepts only the specified status codes.
     */
    public func acceptOnlyStatusCode(
        _ statusCodes: StatusCodeSet
    ) -> ModifiedTask<Modifiers.AcceptOnlyStatusCode<Self>> {
        modify(Modifiers.AcceptOnlyStatusCode(statusCodes))
    }
}
