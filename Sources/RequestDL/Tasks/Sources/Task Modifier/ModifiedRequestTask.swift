/*
 See LICENSE for this package's licensing information.
*/

import Foundation

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
