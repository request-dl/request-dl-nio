/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /// A modifier that accepts only a specific set of status codes as a successful result.
    public struct AcceptOnlyStatusCode<Content: Task>: TaskModifier where Content.Element: TaskResultPrimitive {

        // MARK: - Internal properties

        let statusCodes: StatusCodeSet

        // MARK: - Public methods

        /**
         Modifies a task to accept only the specified status codes.

         - Parameter task: The task to modify.
         - Returns: The modified task that accepts only the specified status codes.
         - Throws: An `InvalidStatusCodeError` if the status code of the result is not
         included in the set of accepted status codes.
         */
        public func task(_ task: Content) async throws -> Content.Element {
            let result = try await task.result()

            guard
                statusCodes.isEmpty || statusCodes.contains(StatusCode(result.head.status.code))
            else {
                throw InvalidStatusCodeError<Content.Element>(data: result)
            }

            return result
        }
    }
}

// MARK: - Task extension

extension Task where Element: TaskResultPrimitive {

    /**
     Returns a modified task that accepts only the specified status codes.

     - Parameter statusCodes: The set of status codes to accept.
     - Returns: A modified task that accepts only the specified status codes.
     */
    public func acceptOnlyStatusCode(
        _ statusCodes: StatusCodeSet
    ) -> ModifiedTask<Modifiers.AcceptOnlyStatusCode<Self>> {
        modify(Modifiers.AcceptOnlyStatusCode(statusCodes: statusCodes))
    }
}
