/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A task modifier that allows the customization of error handling based on the HTTP status
     code of the response.

     `OnStatusCode` modifies the behavior of a `Task` by executing a provided closure when
     the HTTP status code of the response satisfies a certain condition. It only works on tasks that
     return a `TaskResultPrimitive`, which is implemented by `TaskResult<Element>`.

     This modifier is particularly useful when you need to throw a specific error for a certain status code,
     providing a cleaner and more organized error handling approach.
     */
    public struct OnStatusCode<Content: Task>: TaskModifier where Content.Element: TaskResultPrimitive {

        private let contains: (StatusCode) -> Bool
        private let mapHandler: (Content.Element) throws -> Void

        init(
            contains: @escaping (StatusCode) -> Bool,
            map: @escaping (Content.Element) throws -> Void
        ) {
            self.contains = contains
            self.mapHandler = map
        }

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

            try mapHandler(result)
            return result
        }
    }
}

extension Task where Element: TaskResultPrimitive {

    private func onStatusCode(
        _ map: @escaping (Element) throws -> Void,
        contains: @escaping (StatusCode) -> Bool
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        modify(.init(
            contains: contains,
            map: map
        ))
    }

    /**
     Modifies the behavior of the given task by executing the provided closure when the
     HTTP status code of the response satisfies a certain condition.

     - Parameters:
        - statusCode: The range of status codes that satisfy the specified condition.
        - mapHandler: The closure to be executed when the HTTP status code of the
     response satisfies the specified condition.

     - Returns: The modified task with the `OnStatusCode` modifier applied.
     */
    public func onStatusCode(
        _ statusCode: Range<StatusCode>,
        _ mapHandler: @escaping (Element) throws -> Void
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        onStatusCode(mapHandler) {
            statusCode.contains($0)
        }
    }

    /**
     Modifies the behavior of the given task by executing the provided closure when the HTTP
     status code of the response satisfies a certain condition.

     - Parameters:
        - statusCode: The set of status codes that satisfy the specified condition.
        - mapHandler: The closure to be executed when the HTTP status code of the response
     satisfies the specified condition.

     - Returns: The modified task with the `OnStatusCode` modifier applied.
     */
    public func onStatusCode(
        _ statusCode: StatusCodeSet,
        _ mapHandler: @escaping (Element) throws -> Void
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        onStatusCode(mapHandler) {
            statusCode.contains($0)
        }
    }

    /**
     Modifies the behavior of the given task by executing the provided closure when the HTTP
     status code of the response satisfies a certain condition.

     - Parameters:
        - statusCode: The status code that satisfies the specified condition.
        - mapHandler: The closure to be executed when the HTTP status code of the response
     satisfies the specified condition.

     - Returns: The modified task with the `OnStatusCode` modifier applied.
     */
    public func onStatusCode(
        _ statusCode: StatusCode,
        _ mapHandler: @escaping (Element) throws -> Void
    ) -> ModifiedTask<Modifiers.OnStatusCode<Self>> {
        onStatusCode(mapHandler) {
            statusCode == $0
        }
    }
}
