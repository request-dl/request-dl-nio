//
// See LICENSE for this package's licensing information.
//

/// Backs `monitor(_:)`. Queues the monitor on the environment instead of acting on the task
/// itself: only `RawTask`, sitting under whatever chain of modifiers wraps it, actually runs a
/// transfer there is anything to observe on.
struct MonitoredRequestTask<Task: RequestTask>: RequestTask {

    // MARK: - Internal properties

    let task: Task
    let monitor: any RequestMonitor

    // MARK: - Internal methods

    func _result(environment: RequestEnvironmentValues) async throws -> Task.Element {
        var environment = environment
        environment.requestMonitors.append(monitor)
        return try await task._result(environment: environment)
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    ///
    /// Attaches `monitor` to this task, so it is told how much of the request and response bodies
    /// has crossed the network, and what state each execution is in.
    ///
    /// Nothing runs until the returned task is: it composes lazily, the same way ``modifier(_:)``
    /// does. Works anywhere in a task chain, and with any task, since it queues the monitor on the
    /// environment rather than depending on the task in front of it exposing anything special. A
    /// task with nothing to transfer (a mock, for instance) simply never calls it.
    ///
    /// A task may have several monitors, and a monitor may be attached to many tasks.
    ///
    /// - Parameter monitor: The ``RequestMonitor`` to tell.
    /// - Returns: A task that produces this task's actual result, exactly as ``result()`` would.
    ///
    public func monitor(_ monitor: some RequestMonitor) -> AnyTask<Element> {
        MonitoredRequestTask(task: self, monitor: monitor)
            .eraseToAnyTask()
    }
}
