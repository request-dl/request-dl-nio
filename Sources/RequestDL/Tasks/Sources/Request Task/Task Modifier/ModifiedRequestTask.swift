/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type that represents a task that has been modified by a ``RequestTaskModifier``.

 A ``ModifiedRequestTask`` is created by applying a ``RequestTask/modifier(_:)`` to a base
 ``RequestTask``.

 > Note: The `Element` associated type of the ``ModifiedRequestTask`` is determined by the `Output`
 associated type of the ``RequestTaskModifier``.
 */
public struct ModifiedRequestTask<Modifier: RequestTaskModifier>: RequestTask {

    public typealias Element = Modifier.Output

    // MARK: - Internal properties

    let task: Modifier.Content
    let modifier: Modifier

    // MARK: - Public properties

    /**
     Returns the result of the task.

     - Throws: An error of type `Error` if the task could not be completed.

     - Returns: An object of type `Element` with the result of the task.
     */
    public func result() async throws -> Element {
        try await modifier.body(task)
    }
}
