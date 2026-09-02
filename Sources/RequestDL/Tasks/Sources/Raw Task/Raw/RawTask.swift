//
// See LICENSE for this package's licensing information.
//

import NIOHTTP1
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

        let deadline = Internals.ResourceDeadline(nanoseconds: resolved.session.configuration.timeout.resource)

        if let constraints = resolved.session.configuration.networkPathConstraints {
            do {
                try await Internals.NetworkPathGate.wait(for: constraints)
            } catch let error as Internals.NetworkPathUnsatisfiedError {
                throw NetworkAvailabilityError(error)
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

        typealias OnResponseHead = @Sendable (Result<Internals.ResponseHead, Error>) -> Void

        // Owns the whole span lifecycle itself -- start, header injection, attributes, and end --
        // rather than handing `tracer` to `async-http-client`'s own `tracing.tracer`. That built-in
        // instrumentation only starts its span after hopping onto a SwiftNIO `EventLoop`, which loses
        // Swift's task-locals and makes it structurally impossible for it to see whatever
        // `ServiceContext` the caller bound. Running the whole thing here, one layer up and entirely
        // within the caller's own task, sidesteps that.
        //
        // A cache hit (the `.task` case below) never reaches the network, so it isn't traced.
        //
        // `@Sendable` because `Internals.ResourceDeadline.race(seed:_:)` below runs it as a real
        // task-group child task when `Timeout(.resource)` is configured, not just called inline
        // in this task -- otherwise the race is a plain `await` with no isolation change at all.
        @Sendable
        func executeSessionTask() async throws -> (task: SessionTask, onResponseHead: OnResponseHead?) {
            switch await cacheControl(client) {
            case .task(let task):
                return (task, nil)
            case .cache(let cache):
                var request = try resolved.requestConfiguration.build(eventLoop: client.eventLoopGroup.any())

                let tracer = resolved.session.configuration.tracer
                let span = tracer.startSpan(request.method.rawValue, ofKind: .client)
                span.attributes["http.request.method"] = SpanAttribute.string(request.method.rawValue)
                span.attributes["url.full"] = SpanAttribute.string(resolved.requestConfiguration.url)

                tracer.inject(span.context, into: &request.headers, using: HTTPHeadersInjector())

                do {
                    let task = try await resolved.session.execute(
                        client: client,
                        request: request,
                        url: resolved.requestConfiguration.url,
                        readingMode: resolved.requestConfiguration.readingMode,
                        uploadingBytes: resolved.requestConfiguration.body?.totalSize ?? .zero,
                        cache: cache,
                        logger: logger
                    )

                    return (
                        task,
                        { result in
                            switch result {
                            case .success(let head):
                                span.attributes["http.response.status_code"] = SpanAttribute.int64(
                                    Int64(head.status.code)
                                )
                                span.attributes["network.protocol.version"] = SpanAttribute.string(
                                    "\(head.version.major).\(head.version.minor)"
                                )

                                if head.status.code >= 400 {
                                    span.setStatus(.init(code: .error))
                                }
                            case .failure(let error):
                                span.recordError(error)
                                span.setStatus(.init(code: .error))
                            }

                            span.end()
                        }
                    )
                } catch {
                    span.recordError(error)
                    span.setStatus(.init(code: .error))
                    span.end()
                    throw error
                }
            }
        }

        let sessionTask: SessionTask
        let onResponseHead: OnResponseHead?

        // Only rebinds the task-local when `RequestServiceContext` was actually declared -- leaving
        // it untouched otherwise preserves whatever `ServiceContext.current` the caller's own task
        // already carries. The span started above reads this same task-local, so both the explicit
        // and the ambient case are picked up correctly here -- there's no `EventLoop` hop between the
        // bind and the read.
        do {
            if let serviceContext = resolved.requestConfiguration.serviceContext {
                (sessionTask, onResponseHead) = try await deadline.race {
                    try await ServiceContext.$current.withValue(serviceContext) {
                        try await executeSessionTask()
                    }
                }
            } else {
                (sessionTask, onResponseHead) = try await deadline.race(executeSessionTask)
            }
        } catch is Internals.ResourceTimeoutError {
            throw ResourceTimeoutError()
        }

        return AsyncResponse(
            seed: sessionTask.seed,
            response: sessionTask.response,
            onResponseHead: onResponseHead,
            deadline: deadline
        )
    }
}

private struct HTTPHeadersInjector: Injector {

    func inject(_ value: String, forKey key: String, into headers: inout NIOHTTP1.HTTPHeaders) {
        headers.add(name: key, value: value)
    }
}
