//
// See LICENSE for this package's licensing information.
//

import NIOHTTP1
import RequestDLInternals
import Tracing

#if canImport(FoundationEssentials)
import struct FoundationEssentials.URLComponents
#else
import struct Foundation.URLComponents
#endif

struct RawTask<Content: Property>: RequestTask {

    // MARK: - Internal properties

    let content: Content

    // MARK: - Internal methods

    func _result(environment: RequestEnvironmentValues) async throws -> AsyncResponse {
        let resolved = try await Resolve(
            root: content,
            environment: environment
        ).build()

        try await notifyDescriptorHooks(resolved: resolved, environment: environment)

        // Checked before anything else touches `resolved` -- a hard-pinned executor this
        // configuration can't actually run on must fail loudly, not after paying for a
        // logger/client/cache setup nobody will get to use.
        try validateRequiredExecutor(resolved: resolved)

        let deadline = Internals.ResourceDeadline(nanoseconds: resolved.session.configuration.timeout.resource)

        try await waitForNetworkPath(resolved: resolved)

        let logger = Internals.TaskLogger(
            baseURL: resolved.requestConfiguration.baseURL,
            pathComponents: resolved.requestConfiguration.pathComponents,
            logger: environment.logger
        )

        let client = try await resolveClient(resolved: resolved)

        let cacheControl = Internals.CacheControl(
            requestConfiguration: resolved.requestConfiguration,
            dataCache: resolved.dataCache,
            logger: logger
        )

        let (sessionTask, onResponseHead) = try await runSession(
            resolved: resolved,
            client: client,
            cacheControl: cacheControl,
            logger: logger,
            deadline: deadline
        )

        return AsyncResponse(
            seed: sessionTask.seed,
            response: sessionTask.response,
            onResponseHead: onResponseHead,
            deadline: deadline
        )
    }

    // MARK: - Private methods, setup

    /// Hands the exact configuration this request is about to send to every
    /// `description(_:enabled:onDescribe:)` hook queued on `environment` -- before anything
    /// downstream gets a chance to fail, so a hook still sees the resolved request even if the
    /// executor check or the request itself doesn't go through.
    private func notifyDescriptorHooks(
        resolved: Resolved,
        environment: RequestEnvironmentValues
    ) async throws {
        for hook in environment.taskDescriptorContextHooks {
            try await hook(
                TaskDescriptorContext(
                    requestConfiguration: resolved.requestConfiguration,
                    formFields: environment.descriptorFormFields?.fields ?? []
                )
            )
        }
    }

    private func validateRequiredExecutor(resolved: Resolved) throws {
        guard let requiredExecutor = resolved.session.configuration.requiredExecutor else {
            return
        }

        do {
            try resolved.session.configuration.requireExecutor(requiredExecutor)
        } catch let error as Internals.IncompatibleExecutorConfigurationError {
            throw ExecutorRequirementError(error)
        }
    }

    private func waitForNetworkPath(resolved: Resolved) async throws {
        guard let constraints = resolved.session.configuration.networkPathConstraints else {
            return
        }

        do {
            try await Internals.NetworkPathGate.wait(for: constraints)
        } catch let error as Internals.NetworkPathUnsatisfiedError {
            throw NetworkAvailabilityError(error)
        }
    }

    /// `resolvedClient()` -- not `client()` -- is what makes `preferredExecutor`/
    /// `requiredExecutor` (validated by `validateRequiredExecutor(resolved:)`, for the hard-pin
    /// case) actually decide which backend this request runs over, instead of always the NIO
    /// one. `resolvedClient()` returns `Internals.ClientManager.Client` (an enum), not
    /// `any RequestExecutingClient` directly -- see that method's own doc comment for why -- so
    /// this is the one place that unwraps it into the existential everything below expects.
    private func resolveClient(resolved: Resolved) async throws -> any RequestExecutingClient {
        do {
            switch try await resolved.session.resolvedClient() {
            case .nio(let nioClient):
                return nioClient
            #if canImport(Darwin)
            case .urlSession(let urlSessionClient):
                return urlSessionClient
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
    }

    // MARK: - Private methods, session execution

    private typealias OnResponseHead = @Sendable (Result<Internals.ResponseHead, Error>) -> Void

    /// Runs the resolved request to completion, racing it against `deadline` and -- only when
    /// `RequestServiceContext` was actually declared -- binding `ServiceContext.current` for its
    /// duration.
    ///
    /// Only rebinds the task-local when `RequestServiceContext` was actually declared -- leaving
    /// it untouched otherwise preserves whatever `ServiceContext.current` the caller's own task
    /// already carries. `executeTraced(resolved:client:cache:logger:)` starts its span reading
    /// this same task-local, so both the explicit and the ambient case are picked up correctly
    /// here -- there's no `EventLoop` hop between the bind and the read.
    private func runSession(
        resolved: Resolved,
        client: any RequestExecutingClient,
        cacheControl: Internals.CacheControl,
        logger: Internals.TaskLogger?,
        deadline: Internals.ResourceDeadline
    ) async throws -> (task: SessionTask, onResponseHead: OnResponseHead?) {
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
                return try await Self.executeTraced(
                    resolved: resolved,
                    client: client,
                    cache: cache,
                    logger: logger
                )
            }
        }

        do {
            if let serviceContext = resolved.requestConfiguration.serviceContext {
                return try await deadline.race {
                    try await ServiceContext.$current.withValue(serviceContext) {
                        try await executeSessionTask()
                    }
                }
            } else {
                return try await deadline.race(executeSessionTask)
            }
        } catch is Internals.ResourceTimeoutError {
            throw ResourceTimeoutError()
        }
    }

    /// Owns the whole span lifecycle itself -- start, header injection, attributes, and end --
    /// rather than handing `tracer` to `async-http-client`'s own `tracing.tracer`. That built-in
    /// instrumentation only starts its span after hopping onto a SwiftNIO `EventLoop`, which loses
    /// Swift's task-locals and makes it structurally impossible for it to see whatever
    /// `ServiceContext` the caller bound. Running the whole thing here, one layer up and entirely
    /// within the caller's own task, sidesteps that.
    ///
    /// A `RequestConfiguration` copy, not a NIO-specific `HTTPClient.Request` -- the span context
    /// has to reach the wire for both `.nio` and `.urlSession`, and
    /// `client.execute(configuration:cache:logger:)` (`RequestExecutingClient`, not
    /// `Internals.Session.execute`) is what stays transport-agnostic. Every conformance builds its
    /// own transport request straight from `configuration.headers`, so injecting the span context
    /// here reaches whichever backend `resolvedClient()` picked.
    private static func executeTraced(
        resolved: Resolved,
        client: any RequestExecutingClient,
        cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
        logger: Internals.TaskLogger?
    ) async throws -> (task: SessionTask, onResponseHead: OnResponseHead?) {
        var configuration = resolved.requestConfiguration

        try await configuration.applyCompression(
            resolved.session.configuration.compression,
            onDuplicateHeader: resolved.session.configuration.compressionDuplicateHeaderBehavior,
            shouldCompressBodyData: resolved.session.configuration.shouldCompressBodyData
        )

        let tracer = resolved.session.configuration.tracer
        let span = startRequestSpan(tracer: tracer, configuration: &configuration)

        do {
            let task = try await client.execute(
                configuration: configuration,
                cache: cache,
                logger: logger
            )

            return (task, { result in endRequestSpan(span, with: result) })
        } catch {
            span.recordError(error)
            span.setStatus(.init(code: .error))
            span.end()
            throw error
        }
    }

    // MARK: - Private static methods, tracing

    /// Starts the request span, sets its request-side attributes, and injects it into
    /// `configuration.headers` as W3C trace headers -- everything the span needs before the
    /// request actually goes out on the wire.
    private static func startRequestSpan(
        tracer: any Tracer,
        configuration: inout RequestConfiguration
    ) -> any Span {
        let method = configuration.method ?? "GET"
        let span = tracer.startSpan(method, ofKind: .client)

        span.attributes["http.request.method"] = SpanAttribute.string(method)
        span.attributes["url.full"] = SpanAttribute.string(configuration.url)
        setURLAttributes(on: span, url: configuration.url)

        if let body = configuration.body {
            span.attributes["http.request.body.size"] = SpanAttribute.int64(Int64(body.totalSize))
        }

        tracer.inject(span.context, into: &configuration.headers, using: HTTPHeadersInjector())
        return span
    }

    /// Mirrors what async-http-client's own built-in tracing sets on the request span as of
    /// https://github.com/swift-server/async-http-client/pull/906 -- `url.query` is deliberately
    /// left out, since query strings can carry tokens/PII that shouldn't end up on a span by
    /// default.
    private static func setURLAttributes(on span: any Span, url: String) {
        guard let components = URLComponents(string: url) else {
            return
        }

        if let scheme = components.scheme {
            span.attributes["url.scheme"] = SpanAttribute.string(scheme)

            if let host = components.host {
                span.attributes["server.address"] = SpanAttribute.string(host)
            }

            if let port = components.port ?? defaultPort(forScheme: scheme) {
                span.attributes["server.port"] = SpanAttribute.int64(Int64(port))
            }
        }

        if !components.path.isEmpty {
            span.attributes["url.path"] = SpanAttribute.string(components.path)
        }
    }

    /// The port implied by `scheme` when the URL itself doesn't specify one -- mirrors
    /// `async-http-client`'s own `DeconstructedURL`/`Scheme.defaultPort`, so `server.port` on the
    /// span still gets a value for the common `http://example.com` (no explicit port) case.
    private static func defaultPort(forScheme scheme: String) -> Int? {
        switch scheme.lowercased() {
        case "http": 80
        case "https": 443
        default: nil
        }
    }

    private static func endRequestSpan(_ span: any Span, with result: Result<Internals.ResponseHead, Error>) {
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
