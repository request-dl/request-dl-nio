//
// See LICENSE for this package's licensing information.
//

/// Backs `continuingDownload(from:)`. Sets the point on the environment instead of acting on the
/// task itself: only `RawTask`, sitting under whatever chain of modifiers wraps it, actually runs a
/// transfer.
struct ContinuingDownloadFromPointRequestTask<Task: RequestTask>: RequestTask {

    // MARK: - Internal properties

    let task: Task
    let point: DownloadResumptionPoint
    let whenChanged: ChangedDownloadBehavior

    // MARK: - Internal methods

    func _result(environment: RequestEnvironmentValues) async throws -> Task.Element {
        var continuing = environment
        continuing.downloadResumptionStart = point

        do {
            return try await task._result(environment: continuing)
        } catch let error as DownloadResumptionError where whenChanged == .restart && error.reason.isAChange {
            // The head of the continuation was refused before a byte of it reached anyone, so the
            // same request without the point asks for the whole resource, as it would have.
            var restarting = environment
            restarting.downloadResumptionStart = nil
            return try await task._result(environment: restarting)
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    ///
    /// Asks for the rest of a download from `point`, instead of the whole resource, and hands it
    /// on only if it is exactly that.
    ///
    /// Meant for a download that was interrupted, possibly by the application being closed: keep a
    /// ``DownloadResumptionPoint`` (it is `Codable`) and the bytes you received, and continue from
    /// there later. The request is sent with `Range` and `If-Range`, so a resource that changed
    /// since is never spliced onto what you have, and the response is checked before a single byte
    /// of it reaches you. Whatever is wrong with it fails the task with a
    /// ``DownloadResumptionError``, and the download can be started again from the beginning.
    ///
    /// The result is the *rest* of the resource: what comes after ``DownloadResumptionPoint/offset``.
    /// Its head is the `206` the server answered with.
    ///
    /// Always goes to the network, whatever the cache strategy: a cached copy of the whole
    /// resource is not the rest of it.
    ///
    /// Works with ``DownloadTask`` and ``DataTask``, anywhere in a task chain, and together with
    /// ``resumingDownloads(_:)``, which then reconnects from wherever this one got to.
    ///
    /// - Parameters:
    ///   - point: Where the partial download stopped.
    ///   - whenChanged: What to do when the server doesn't answer with the rest of the same
    ///   resource. ``ChangedDownloadBehavior/fail``, the default, fails the task;
    ///   ``ChangedDownloadBehavior/restart`` asks again for the whole resource, which is then the
    ///   result, with a `200` in its head where the rest has a `206`.
    /// - Returns: A task that produces the rest of the download.
    /// - Throws: ``DownloadResumptionError``, when the request can't be continued, or the server's
    /// answer isn't exactly the rest of the same resource and ``ChangedDownloadBehavior/restart``
    /// wasn't asked for. ``DownloadResumptionError/Reason/alreadyComplete``
    /// is not a failure: it says there was nothing left to download.
    ///
    public func continuingDownload(
        from point: DownloadResumptionPoint,
        whenChanged: ChangedDownloadBehavior = .fail
    ) -> AnyTask<Element> {
        ContinuingDownloadFromPointRequestTask(task: self, point: point, whenChanged: whenChanged)
            .eraseToAnyTask()
    }
}
