//
// See LICENSE for this package's licensing information.
//

extension Modifiers {

    /// A task modifier that applies a mapping function to the error of the task, allowing for
    /// error handling and transformation.
    public struct MapError<Input: Sendable>: RequestTaskModifier {

        // MARK: - Internal properties

        let transform: @Sendable (Error) async throws -> Input

        // MARK: - Public methods

        ///
        /// A mapping function that throws a new error or maps the current error into a valid object.
        ///
        /// - Parameter task: The ``RequestTask`` where its error will be mapped.
        /// - Returns: A new error.
        ///
        public func body(_ task: Content) async throws -> Input {
            do {
                return try await task.result()
            } catch is CancellationError {
                // Never handed to `transform`, mirroring `Modifiers.Retry`'s own carve-out: a
                // cancelled task's failure is the caller giving up, not a condition to recover
                // from. A `transform` written as a general "fall back to a safe default on any
                // failure" catch-all would otherwise turn a cancelled `.task(id:)`/structured
                // scope into an apparent success, masking the cancellation from the very
                // structured-concurrency machinery (SwiftUI's own cancellation handling
                // included) that needs to see it to avoid acting on a torn-down view/scope.
                throw CancellationError()
            } catch {
                return try await transform(error)
            }
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    ///
    /// Modifies the behavior of the given task by mapping the error into a new error or in a valid result object.
    ///
    /// - Parameter transform: A mapping function that throws a new error or maps the current error into a valid object.
    /// - Returns: The modified task with the ``Modifiers/MapError`` modifier applied.
    ///
    public func mapError(
        _ transform: @escaping @Sendable (Error) async throws -> Element
    ) -> ModifiedRequestTask<Modifiers.MapError<Element>> {
        modifier(Modifiers.MapError(transform: transform))
    }
}
