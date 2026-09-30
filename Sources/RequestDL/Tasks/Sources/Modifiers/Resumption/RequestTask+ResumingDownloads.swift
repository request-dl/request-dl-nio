//
// See LICENSE for this package's licensing information.
//

extension RequestTask {

    ///
    /// Makes a download that loses its connection mid-body carry on from where it stopped, instead
    /// of failing, when it is safe to (see ``DownloadResumptionPolicy``).
    ///
    /// Off by default: a download that isn't given a policy fails on a lost connection, as it
    /// always did.
    ///
    /// Nothing runs until the returned task is: it composes lazily, the same way ``modifier(_:)``
    /// does. Works anywhere in a task chain, directly on ``DownloadTask``/``DataTask`` or after any
    /// modifier, since it sets the policy on the environment (see ``environment(_:_:)``) rather
    /// than depending on the task in front of it exposing anything special. When a task has
    /// several, the one closest to it wins, so a later `.resumingDownloads(.disabled)` doesn't
    /// undo an earlier, inner one.
    ///
    /// Reconnection waits while a ``RequestController`` attached to the task is suspended: a
    /// paused transfer never opens a new connection behind the application's back.
    ///
    /// - Parameter policy: Whether, and how, to reconnect. Defaults to ``DownloadResumptionPolicy/enabled(maximumAttemptsWithoutProgress:delay:)``.
    /// - Returns: A task that produces this task's actual result, exactly as ``result()`` would.
    ///
    public func resumingDownloads(
        _ policy: DownloadResumptionPolicy = .enabled()
    ) -> ModifiedRequestTask<Modifiers.Environment<Element>> {
        environment(\.downloadResumptionPolicy, policy)
    }
}
