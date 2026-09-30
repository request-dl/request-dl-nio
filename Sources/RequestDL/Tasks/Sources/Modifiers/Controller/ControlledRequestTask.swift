//
// See LICENSE for this package's licensing information.
//

/// Backs `controller(_:)`. Queues the controller on the environment instead of acting on the
/// task itself: there's no generic way to suspend an arbitrary `RequestTask`, only `RawTask`,
/// sitting under whatever chain of modifiers wraps it, actually runs a transfer.
struct ControlledRequestTask<Task: RequestTask>: RequestTask {

    // MARK: - Internal properties

    let task: Task
    let controller: RequestController

    // MARK: - Internal methods

    func _result(environment: RequestEnvironmentValues) async throws -> Task.Element {
        var environment = environment
        environment.requestControllers.append(controller)
        return try await task._result(environment: environment)
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    ///
    /// Attaches `controller` to this task, so ``RequestController/suspend()`` and
    /// ``RequestController/resume()`` pause and continue its transfer.
    ///
    /// Nothing runs until the returned task is: it composes lazily, the same way ``modifier(_:)``
    /// does. Works anywhere in a task chain, directly on ``DataTask``/``DownloadTask``/
    /// ``UploadTask`` or after any modifier, since it queues the controller on the environment
    /// rather than depending on the task in front of it exposing anything special. A task with
    /// nothing to transfer (a mock, for instance) simply ignores it.
    ///
    /// One controller may be attached to many tasks, and a task may have several controllers.
    ///
    /// - Parameter controller: The ``RequestController`` that suspends and resumes the task.
    /// - Returns: A task that produces this task's actual result, exactly as ``result()`` would.
    ///
    public func controller(_ controller: RequestController) -> AnyTask<Element> {
        ControlledRequestTask(task: self, controller: controller)
            .eraseToAnyTask()
    }
}
