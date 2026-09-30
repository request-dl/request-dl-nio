//
// See LICENSE for this package's licensing information.
//

extension RequestTask {

    ///
    /// Attaches `monitor` to this task, so it is told how much of the request and response bodies
    /// has crossed the network, and what state each execution is in.
    ///
    /// Nothing runs until the returned task is: it composes lazily, the same way ``modifier(_:)``
    /// does. Works anywhere in a task chain, and with any task, since it queues the monitor on the
    /// environment (see ``environment(_:_:)``) rather than depending on the task in front of it
    /// exposing anything special. A task with nothing to transfer (a mock, for instance) simply
    /// never calls it.
    ///
    /// A task may have several monitors, and a monitor may be attached to many tasks.
    ///
    /// - Parameter monitor: The ``RequestMonitor`` to tell.
    /// - Returns: A task that produces this task's actual result, exactly as ``result()`` would.
    ///
    public func monitor(
        _ monitor: some RequestMonitor
    ) -> ModifiedRequestTask<Modifiers.Environment<Element>> {
        // Appended, not set: a second `.monitor(_:)` in the chain adds to the first, which
        // `environment(_:_:)`, being a plain assignment, couldn't do.
        modifier(
            Modifiers.Environment {
                $0.requestMonitors.append(monitor)
            }
        )
    }
}
