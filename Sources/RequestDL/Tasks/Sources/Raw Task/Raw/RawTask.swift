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

    func _result(environment: RequestEnvironmentValues) async throws -> AsyncResponse {
        let resolved = try await Resolve(
            root: content,
            environment: environment
        ).build()

        // Hands the exact configuration this request is about to send to every
        // `description(_:enabled:onDescribe:)` hook queued on `environment` -- before anything
        // downstream gets a chance to fail, so a hook still sees the resolved request even if the
        // executor check or the request itself doesn't go through.
        for hook in environment.taskDescriptorContextHooks {
            try await hook(
                TaskDescriptorContext(
                    requestConfiguration: resolved.requestConfiguration,
                    formFields: environment.descriptorFormFields?.fields ?? []
                )
            )
        }

        // Checked before anything else touches `resolved` -- a hard-pinned executor this
        // configuration can't actually run on must fail loudly, not after paying for a
        // logger/client/cache setup nobody will get to use.
        if let requiredExecutor = resolved.session.configuration.requiredExecutor {
            do {
                try resolved.session.configuration.requireExecutor(requiredExecutor)
            } catch let error as Internals.IncompatibleExecutorConfigurationError {
                throw ExecutorRequirementError(error)
            }
        }

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

        // `resolvedClient()` -- not `client()` -- is what makes `preferredExecutor`/
        // `requiredExecutor` (validated just above, for the hard-pin case) actually decide which
        // backend this request runs over, instead of always the NIO one. `resolvedClient()`
        // returns `Internals.ClientManager.Client` (an enum), not `any RequestExecutingClient`
        // directly -- see that method's own doc comment for why -- so this is the one place that
        // unwraps it into the existential everything below expects.
        let client: any RequestExecutingClient

        do {
            switch try await resolved.session.resolvedClient() {
            case .nio(let nioClient):
                client = nioClient
            #if canImport(Darwin)
            case .urlSession(let urlSessionClient):
                client = urlSessionClient
            #endif
            }
        } catch let error as Internals.SecureFileLoadError {
            throw SecureFileError(error)
        } catch {
            #if canImport(Darwin)
            if let error = error as? Internals.URLSessionIdentityPolicy.ConfigurationError {
                throw ClientIdentityError(error)
            }
            if let error = error as? Internals.RawBytesIdentityBuilder.Error {
                throw ClientIdentityError(error)
            }
            #endif
            throw error
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
                // A `RequestConfiguration` copy, not a NIO-specific `HTTPClient.Request` -- the
                // span context has to reach the wire for both `.nio` and `.urlSession`, and
                // `client.execute(configuration:cache:logger:)` (`RequestExecutingClient`, not
                // `Internals.Session.execute`) is what stays transport-agnostic. Every conformance
                // builds its own transport request straight from `configuration.headers`, so
                // injecting here reaches whichever backend `resolvedClient()` picked.
                var configuration = resolved.requestConfiguration
                let method = configuration.method ?? "GET"

                let tracer = resolved.session.configuration.tracer
                let span = tracer.startSpan(method, ofKind: .client)
                span.attributes["http.request.method"] = SpanAttribute.string(method)
                span.attributes["url.full"] = SpanAttribute.string(configuration.url)

                tracer.inject(span.context, into: &configuration.headers, using: HTTPHeadersInjector())

                do {
                    let task = try await client.execute(
                        configuration: configuration,
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

extension RawTask {

    /// Resolves `content` and hands the result to `descriptor`, without executing a request.
    ///
    /// Not part of the `_result(environment:)` chain — like `RequestTask.result()`'s own default
    /// (`_result(environment: RequestEnvironmentValues())`), this is an entry point, not
    /// something nested inside another task's `.environment()`. `descriptorFormFields` is set on
    /// that fresh environment and threaded through `Resolve.init(root:environment:)` into
    /// `_PropertyInputs.environment`, which is how `FormNode` — the only node that needs to know
    /// a description pass is running, since it's the only place per-field structure would
    /// otherwise be lost to multipart flattening — receives it: captured by `Form`/`FormGroup`'s
    /// own `_makeProperty` at construction time, not read from inside `make()` itself (nodes have
    /// no `environment` of their own to read there). `partiallyBuild()`, unlike `build()`, never
    /// constructs an `Internals.Session` or resolves a client, which is exactly right here:
    /// nothing about producing a description touches the network.
    func description<Descriptor: TaskDescriptor>(_ descriptor: Descriptor) async throws -> Descriptor.Output {
        let formFieldBox = DescriptorFormFieldBox()

        var environment = RequestEnvironmentValues()
        environment.descriptorFormFields = formFieldBox

        let (_, make) = try await Resolve(root: content, environment: environment).partiallyBuild()

        return try await descriptor.describe(
            TaskDescriptorContext(
                requestConfiguration: make.requestConfiguration,
                formFields: formFieldBox.fields
            )
        )
    }
}

private struct HTTPHeadersInjector: Injector {

    func inject(_ value: String, forKey key: String, into headers: inout HTTPHeaders) {
        headers.add(name: key, value: value)
    }
}
