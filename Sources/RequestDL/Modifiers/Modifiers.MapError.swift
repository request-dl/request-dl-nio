//
//  Modifiers.MapError.swift
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

extension Modifiers {

    /// A task modifier that applies a mapping function to the error of the task, allowing for
    /// error handling and transformation.
    public struct MapError<Content: Task>: TaskModifier {

        // swiftlint:disable nesting
        public typealias Element = Content.Element

        let mapErrorHandler: (Error) throws -> Element

        init(mapErrorHandler: @escaping (Error) throws -> Element) {
            self.mapErrorHandler = mapErrorHandler
        }

        /**
         A mapping function that transforms the error of the task result to a new error.

         - Parameter task: A `Task` that returns a `TaskResult` containing the error to map.
         - Returns: A new error.
         */
        public func task(_ task: Content) async throws -> Element {
            do {
                return try await task.response()
            } catch {
                return try mapErrorHandler(error)
            }
        }
    }
}

extension Task {

    /**
     Returns a new `Task` with the error of the original `Task` mapped to a new error.

     - Parameter mapErrorHandler: A mapping function that transforms the error of the
     task result to a new error.
     - Returns: A new `Task` with the mapped error.
     */
    public func mapError(
        _ mapErrorHandler: @escaping (Error) throws -> Element
    ) -> ModifiedTask<Modifiers.MapError<Self>> {
        modify(Modifiers.MapError(mapErrorHandler: mapErrorHandler))
    }
}
