/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /// A request task modifier that collects and combines individual steps into a consolidated `AsyncBytes` object.
    public struct CollectBytes: RequestTaskModifier {

        public typealias Input = AsyncResponse

        // MARK: - Inits

        fileprivate init() {}

        // MARK: - Public methods

        /**
         Combines individual steps into `AsyncBytes` object.

         - Parameter task: The request task to modify.
         - Returns: The task result.
         - Throws: An error if the modification fails.
         */
        public func body(_ task: Content) async throws -> TaskResult<AsyncBytes> {
            try await task.result().collect()
        }
    }
}

// MARK: - RequestTask extension

// swiftlint:disable line_length
extension RequestTask<AsyncResponse> {

    /// Returns a modified request task that collects and combines individual steps into a consolidated `AsyncBytes` object.
    public func collectBytes() -> ModifiedRequestTask<Modifiers.CollectBytes> {
        modifier(Modifiers.CollectBytes())
    }
}
// swiftlint:enable line_length
