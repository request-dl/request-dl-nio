/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A `TaskModifier` that transforms the element of the given `RequestTask` using the
     provided closure.

     Use the `map` modifier to transform the `Element` of a `RequestTask` to a different type
     of element. You can provide a closure that takes the original element as input and
     returns a new element of the desired type. The closure throws an error if the transformation
     fails, and the `RequestTask` fails with the same error.

     ```swift
     DataTask { ... }
         .map { result in
             try JSONDecoder().decode(MyModel.self, from: result.data)
         }
     ```

     In this example, the `RequestTask` produces `Data` elements, but you can use the `map`
     modifier to decode them into `MyModel` instances instead.
     */
    public struct Map<Input: Sendable, Output: Sendable>: RequestTaskModifier {

        // MARK: - Internal properties

        let transform: @Sendable (Input) throws -> Output

        // MARK: - Public methods

        /**
         Transforms the element of the given `RequestTask` using the provided closure.

         - Parameter task: The `RequestTask` to modify.
         - Returns: The transformed element.
         - Throws: The error thrown by the closure, if any.
         */
        public func body(_ task: Content) async throws -> Output {
            try transform(await task.result())
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    /**
     Transforms the element of the `RequestTask` using the provided closure.

     - Parameter transform: The closure that transforms the original element.
     - Returns: A modified `RequestTask` with the transformed element.
     */
    public func map<NewElement>(
        _ transform: @escaping @Sendable (Element) throws -> NewElement
    ) -> ModifiedRequestTask<Modifiers.Map<Element, NewElement>> {
        modifier(Modifiers.Map(transform: transform))
    }
}
