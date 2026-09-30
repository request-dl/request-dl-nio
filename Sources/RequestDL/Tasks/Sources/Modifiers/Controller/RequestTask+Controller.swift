//
// See LICENSE for this package's licensing information.
//

extension RequestTask {

    ///
    /// Attaches `controller` to this task, so ``RequestController/suspend()`` and
    /// ``RequestController/resume()`` pause and continue its transfer.
    ///
    /// Nothing runs until the returned task is: it composes lazily, the same way ``modifier(_:)``
    /// does. Works anywhere in a task chain, directly on ``DataTask``/``DownloadTask``/
    /// ``UploadTask`` or after any modifier, since it queues the controller on the environment
    /// (see ``environment(_:_:)``) rather than depending on the task in front of it exposing
    /// anything special. A task with nothing to transfer (a mock, for instance) simply ignores it.
    ///
    /// One controller may be attached to many tasks, and a task may have several controllers.
    ///
    /// - Parameter controller: The ``RequestController`` that suspends and resumes the task.
    /// - Returns: A task that produces this task's actual result, exactly as ``result()`` would.
    ///
    public func controller(
        _ controller: RequestController
    ) -> ModifiedRequestTask<Modifiers.Environment<Element>> {
        // Appended, not set: a second `.controller(_:)` in the chain adds to the first, which
        // `environment(_:_:)`, being a plain assignment, couldn't do.
        modifier(
            Modifiers.Environment {
                $0.requestControllers.append(controller)
            }
        )
    }
}
