/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Logging

extension Modifiers {

    /// A modifier that adds a logger to a request task.
    public struct Logger<Input: Sendable>: RequestTaskModifier {

        // MARK: - Internal properties

        let logger: Logging.Logger

        // MARK: - Public methods

        /**
         Applies the logger to the request task.

         - Parameter task: The request task to modify.
         - Returns: The task result.
         - Throws: An error if the modification fails.
         */
        public func body(_ task: Content) async throws -> Input {
            try await task
                .environment(\.logger, logger)
                .result()
        }
    }
}

extension RequestTask {

    /**
     Adds a logger to the request task.

     - Parameter logger: The logger to add.
     - Returns: A modified request task with the added logger.
     */
    public func logger(
        _ logger: Logger
    ) -> ModifiedRequestTask<Modifiers.Logger<Element>> {
        modifier(Modifiers.Logger(logger: logger))
    }
}
