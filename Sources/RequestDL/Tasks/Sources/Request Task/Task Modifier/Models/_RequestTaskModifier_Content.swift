/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// This struct is marked as internal and is not intended
/// to be used directly by clients of this framework.
public struct _RequestTaskModifier_Content<Modifier: RequestTaskModifier>: RequestTask {

    // MARK: - Private properties

    private var task: any RequestTask<Modifier.Input>

    // MARK: - Inits

    init<Content: RequestTask>(_ task: Content) where Content.Element == Modifier.Input {
        self.task = task
    }

    // MARK: - Public methods

    public func result() async throws -> Modifier.Input {
        try await task.result()
    }
}
