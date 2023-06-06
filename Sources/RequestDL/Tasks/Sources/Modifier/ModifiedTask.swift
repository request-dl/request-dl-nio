/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A type that represents a task that has been modified by a `TaskModifier`.

 A `ModifiedTask` is a `RequestTask` that is created by applying a `TaskModifier` to a base
 `RequestTask`.

 - Note: The `Element` associated type of the `ModifiedTask` is determined by the `Element`
 associated type of the `TaskModifier`.
 */
@available(*, deprecated, renamed: "ModifiedRequestTask")
public struct ModifiedTask<Modifier: TaskModifier>: RequestTask {

    public typealias Element = Modifier.Element

    // MARK: - Internal properties

    let task: Modifier.Body
    let modifier: Modifier

    // MARK: - Public properties

    /**
     Returns the result of the task.

     - Throws: An error of type `Error` if the task could not be completed.

     - Returns: An object of type `Element` with the result of the task.
     */
    public func result() async throws -> Element {
        try await modifier.task(task)
    }
}
