//
// See LICENSE for this package's licensing information.
//

extension Modifiers {

    /// A modifier that accepts only a specific set of status codes as a successful result.
    public struct AcceptOnlyStatusCode<Input: TaskResultPrimitive>: RequestTaskModifier {

        // MARK: - Internal properties

        let statusCodes: StatusCodeSet

        // MARK: - Public methods

        ///
        /// Modifies a task to accept only the specified status codes.
        ///
        /// - Parameter task: The task to modify.
        /// - Returns: The modified task that accepts only the specified status codes.
        /// - Throws: An `InvalidStatusCodeError` if the status code of the result is not
        /// included in the set of accepted status codes. An empty set accepts nothing.
        ///
        public func body(_ task: Content) async throws -> Input {
            let result = try await task.result()

            guard statusCodes.contains(StatusCode(result.head.status.code)) else {
                throw InvalidStatusCodeError<Content.Element>(data: result)
            }

            return result
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask where Element: TaskResultPrimitive {

    ///
    /// Returns a modified task that accepts only the specified status codes.
    ///
    /// - Parameter statusCodes: The set of status codes to accept. An empty set (an
    /// intersection with nothing in common, a list read from a configuration with nothing in it)
    /// accepts no status code at all, so every response throws.
    /// - Returns: A modified task that accepts only the specified status codes.
    /// - Throws: An `InvalidStatusCodeError` when the response's status code is not in the set.
    ///
    public func acceptOnlyStatusCode(
        _ statusCodes: StatusCodeSet
    ) -> ModifiedRequestTask<Modifiers.AcceptOnlyStatusCode<Element>> {
        modifier(Modifiers.AcceptOnlyStatusCode(statusCodes: statusCodes))
    }
}
