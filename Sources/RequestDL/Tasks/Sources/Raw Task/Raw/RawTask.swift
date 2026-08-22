//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

struct RawTask<Content: Property>: RequestTask {

    // MARK: - Internal properties

    let content: Content

    // MARK: - Internal methods

    func result() async throws -> AsyncResponse {
        let resolved = try await Resolve(
            root: content,
            environment: environment
        ).build()

        // Checked before anything else touches `resolved` -- a hard-pinned executor this
        // configuration can't actually run on must fail loudly (§6.4 of URLSESSION_REPORT.md),
        // not after paying for a logger/client/cache setup nobody will get to use.
        if let requiredExecutor = resolved.session.configuration.requiredExecutor {
            do {
                try resolved.session.configuration.requireExecutor(requiredExecutor)
            } catch let error as Internals.IncompatibleExecutorConfigurationError {
                throw ExecutorRequirementError(error)
            }
        }

        let logger = Internals.TaskLogger(
            baseURL: resolved.requestConfiguration.baseURL,
            pathComponents: resolved.requestConfiguration.pathComponents,
            logger: environment.logger
        )

        let client: Internals.Client

        do {
            client = try await resolved.session.client()
        } catch let error as Internals.SecureFileLoadError {
            throw SecureFileError(error)
        }

        let cacheControl = Internals.CacheControl(
            requestConfiguration: resolved.requestConfiguration,
            dataCache: resolved.dataCache,
            logger: logger
        )

        let sessionTask: SessionTask

        switch await cacheControl(client) {
        case .task(let task):
            sessionTask = task
        case .cache(let cache):
            sessionTask = try await resolved.session.execute(
                client: client,
                request: try resolved.requestConfiguration.build(eventLoop: client.eventLoopGroup.any()),
                url: resolved.requestConfiguration.url,
                readingMode: resolved.requestConfiguration.readingMode,
                uploadingBytes: resolved.requestConfiguration.body?.totalSize ?? .zero,
                cache: cache,
                logger: logger
            )
        }

        return AsyncResponse(
            seed: sessionTask.seed,
            response: sessionTask.response
        )
    }
}
