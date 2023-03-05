//
//  Modifiers.Map.swift
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

    /**
     A `TaskModifier` that transforms the element of the given `Task` using the
     provided closure.

     Use the `map` modifier to transform the `Element` of a `Task` to a different type
     of element. You can provide a closure that takes the original element as input and
     returns a new element of the desired type. The closure throws an error if the transformation
     fails, and the `Task` fails with the same error.

     ```swift
     DataTask { ... }
         .map { result in
             try JSONDecoder().decode(MyModel.self, from: result.data)
         }
     ```

     In this example, the `Task` produces `Data` elements, but you can use the `map`
     modifier to decode them into `MyModel` instances instead.
     */
    public struct Map<Content: Task, NewElement>: TaskModifier {

        let mapHandler: (Content.Element) throws -> NewElement

        init(mapHandler: @escaping (Content.Element) throws -> NewElement) {
            self.mapHandler = mapHandler
        }
        /**
         Transforms the element of the given `Task` using the provided closure.

         - Parameter task: The `Task` to modify.
         - Returns: The transformed element.
         - Throws: The error thrown by the closure, if any.
         */
        public func task(_ task: Content) async throws -> NewElement {
            try mapHandler(await task.response())
        }
    }
}

extension Task {

    /**
     Transforms the element of the `Task` using the provided closure.

     - Parameter mapHandler: The closure that transforms the original element.
     - Returns: A modified `Task` with the transformed element.
     */
    public func map<NewElement>(
        _ mapHandler: @escaping (Element) throws -> NewElement
    ) -> ModifiedTask<Modifiers.Map<Self, NewElement>> {
        modify(Modifiers.Map(mapHandler: mapHandler))
    }
}
