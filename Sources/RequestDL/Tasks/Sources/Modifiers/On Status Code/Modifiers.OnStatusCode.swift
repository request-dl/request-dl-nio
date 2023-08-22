/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A task modifier that allows the customization of error handling based on the HTTP status
     code of the response.

     This modifier changes the behavior of a ``RequestTask`` by executing a provided closure when
     the HTTP status code of the response satisfies a certain condition. It only works on tasks that
     return a ``TaskResultPrimitive``, which is implemented by ``TaskResult``.

     This modifier is particularly useful when you need to throw a specific error for a certain status code,
     providing a cleaner and more organized error handling approach.
     */
    public struct OnStatusCode<Input: TaskResultPrimitive>: RequestTaskModifier {

        // MARK: - Internal properties

        let contains: @Sendable (StatusCode) -> Bool
        let transform: @Sendable (Input) async throws -> Void

        // MARK: - Public methods

        /**
         A function that modifies the task and returns the result.
         - Parameter task: The modified task.
         - Returns: The result of the modified task.
         - Throws: it can throws the specific error for a certain status code
         */
        public func body(_ task: Content) async throws -> Input {
            let result = try await task.result()

            guard contains(StatusCode(result.head.status.code)) else {
                return result
            }

            try await transform(result)
            return result
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask where Element: TaskResultPrimitive {

    private func onStatusCode(
        _ transform: @escaping @Sendable (Element) async throws -> Void,
        contains: @escaping @Sendable (StatusCode) -> Bool
    ) -> ModifiedRequestTask<Modifiers.OnStatusCode<Element>> {
        modifier(Modifiers.OnStatusCode(
            contains: contains,
            transform: transform
        ))
    }

    /**
     Modifies the behavior of the given task by executing the provided closure when the
     HTTP status code of the response satisfies a certain condition.

     - Parameters:
        - statusCode: The range of status codes that satisfy the specified condition.
        - transform: The closure to be executed when the HTTP status code of the
     response satisfies the specified condition.

     - Returns: The modified task with the ``Modifiers/OnStatusCode`` modifier applied.
     */
    public func onStatusCode(
        _ statusCode: Range<StatusCode>,
        _ transform: @escaping @Sendable (Element) async throws -> Void
    ) -> ModifiedRequestTask<Modifiers.OnStatusCode<Element>> {
        onStatusCode(transform) {
            statusCode.contains($0)
        }
    }

    /**
     Modifies the behavior of the given task by executing the provided closure when the HTTP
     status code of the response satisfies a certain condition.

     - Parameters:
        - statusCode: The set of status codes that satisfy the specified condition.
        - transform: The closure to be executed when the HTTP status code of the response
     satisfies the specified condition.

     - Returns: The modified task with the ``Modifiers/OnStatusCode`` modifier applied.
     */
    public func onStatusCode(
        _ statusCode: StatusCodeSet,
        _ transform: @escaping @Sendable (Element) async throws -> Void
    ) -> ModifiedRequestTask<Modifiers.OnStatusCode<Element>> {
        onStatusCode(transform) {
            statusCode.contains($0)
        }
    }

    /**
     Modifies the behavior of the given task by executing the provided closure when the HTTP
     status code of the response satisfies a certain condition.

     - Parameters:
        - statusCode: The status code that satisfies the specified condition.
        - transform: The closure to be executed when the HTTP status code of the response
     satisfies the specified condition.

     - Returns: The modified task with the ``Modifiers/OnStatusCode`` modifier applied.
     */
    public func onStatusCode(
        _ statusCode: StatusCode,
        _ transform: @escaping @Sendable (Element) async throws -> Void
    ) -> ModifiedRequestTask<Modifiers.OnStatusCode<Element>> {
        onStatusCode(transform) {
            statusCode == $0
        }
    }
}
