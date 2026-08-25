//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Tracing

struct RawTask<Content: Property>: RequestTask {

    // MARK: - Internal properties

    let content: Content

    // MARK: - Internal methods

    func result() async throws -> AsyncResponse {
        let resolved = try await Resolve(
            root: content,
            environment: environment
        ).build()

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

        func executeSessionTask() async throws -> SessionTask {
            switch await cacheControl(client) {
            case .task(let task):
                return task
            case .cache(let cache):
                return try await resolved.session.execute(
                    client: client,
                    request: try resolved.requestConfiguration.build(eventLoop: client.eventLoopGroup.any()),
                    url: resolved.requestConfiguration.url,
                    readingMode: resolved.requestConfiguration.readingMode,
                    uploadingBytes: resolved.requestConfiguration.body?.totalSize ?? .zero,
                    cache: cache,
                    logger: logger
                )
            }
        }

        let sessionTask: SessionTask

        // Only rebinds the task-local when `RequestServiceContext` was actually declared -- leaving
        // it untouched otherwise preserves whatever `ServiceContext.current` the caller's own task
        // already carries, which `async-http-client` picks up on its own.
        if let serviceContext = resolved.requestConfiguration.serviceContext {
            sessionTask = try await ServiceContext.$current.withValue(serviceContext) {
                try await executeSessionTask()
            }
        } else {
            sessionTask = try await executeSessionTask()
        }

        return AsyncResponse(
            seed: sessionTask.seed,
            response: sessionTask.response
        )
    }
}
