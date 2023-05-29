/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A task modifier that allows the customization of error handling based on the HTTP status
     code of the response.

     `OnStatusCode` modifies the behavior of a `RequestTask` by executing a provided closure when
     the HTTP status code of the response satisfies a certain condition. It only works on tasks that
     return a `TaskResultPrimitive`, which is implemented by `TaskResult<Element>`.

     This modifier is particularly useful when you need to throw a specific error for a certain status code,
     providing a cleaner and more organized error handling approach.
     */
    public struct OnStatusCode<Content: RequestTask>: TaskModifier where Content.Element: TaskResultPrimitive {

        // MARK: - Internal properties

        let contains: @Sendable (StatusCode) -> Bool
        let transform: @Sendable (Content.Element) throws -> Void

        // MARK: - Public methods

        /**
         A function that modifies the task and returns the result.
         - Parameter task: The modified task.
         - Returns: The result of the modified task.
         - Throws: it can throws the specific error for a certain status code
         */
        public func task(_ task: Content) async throws -> Content.Element {
            let result = try await task.result()

            guard contains(StatusCode(result.head.status.code)) else {
                return result
            }

            try transform(result)
            return result
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask where Element: TaskResultPrimitive {

    private func onStatusCode(
        _ transform: @escaping @Sendable (Element) throws -> Void,
        contains: @escaping @Sendable (StatusCode) -> Bool
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        modify(.init(
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

     - Returns: The modified task with the `OnStatusCode` modifier applied.
     */
    public func onStatusCode(
        _ statusCode: Range<StatusCode>,
        _ transform: @escaping @Sendable (Element) throws -> Void
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
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

     - Returns: The modified task with the `OnStatusCode` modifier applied.
     */
    public func onStatusCode(
        _ statusCode: StatusCodeSet,
        _ transform: @escaping @Sendable (Element) throws -> Void
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
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

     - Returns: The modified task with the `OnStatusCode` modifier applied.
     */
    public func onStatusCode(
        _ statusCode: StatusCode,
        _ transform: @escaping @Sendable (Element) throws -> Void
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        onStatusCode(transform) {
            statusCode == $0
        }
    }
}
