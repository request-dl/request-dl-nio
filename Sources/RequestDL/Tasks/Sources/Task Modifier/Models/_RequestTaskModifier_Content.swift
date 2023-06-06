/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct _RequestTaskModifier_Content<Modifier: RequestTaskModifier>: RequestTask {

    // MARK: - Private properties

    private let task: any RequestTask<Modifier.Input>

    // MARK: - Inits

    init<Content: RequestTask>(_ task: Content) where Content.Element == Modifier.Input {
        self.task = task
    }

    // MARK: - Public methods

    public func result() async throws -> Modifier.Input {
        try await task.result()
    }
}
