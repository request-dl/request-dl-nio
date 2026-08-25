//
// See LICENSE for this package's licensing information.
//

import NIOConcurrencyHelpers
import Testing
import Tracing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

private enum TestIDKey: ServiceContextKey {
    typealias Value = String
}

extension ServiceContext {
    fileprivate var testID: String? {
        get { self[TestIDKey.self] }
        set { self[TestIDKey.self] = newValue }
    }
}

struct RequestServiceContextTests {

    @Test
    func serviceContext_whenSet_shouldBeAvailableInRequestConfiguration() async throws {
        // Given
        var context = ServiceContext.topLevel
        context.testID = "abc-123"

        let property = TestProperty(RequestServiceContext(context))

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(resolved.requestConfiguration.serviceContext?.testID == "abc-123")
    }

    @Test
    func serviceContext_whenNotDeclared_shouldBeNil() async throws {
        // Given
        let property = TestProperty(RequestMethod(.get))

        // When
        let resolved = try await resolve(property)

        // Then
        #expect(resolved.requestConfiguration.serviceContext == nil)
    }

    @Test
    func serviceContext_whenNeverBody_shouldBeNever() async throws {
        // Given
        let property = RequestServiceContext(.topLevel)

        // Then
        try await assertNever(property.body)
    }

    /// Documents a confirmed upstream bug rather than a RequestDL regression: `async-http-client`
    /// starts a request's span only after execution hops onto a SwiftNIO `EventLoop` via
    /// `EventLoop.execute(_:)`, and Swift's task-locals -- which `ServiceContext.current` is built
    /// on -- don't cross that hop. Root-caused in full in `TRACER_SERVICE_CONTEXT_REPORT.md` at the
    /// repository root. Wrapped in `withKnownIssue` so this stays red-if-fixed instead of
    /// red-forever: once the upstream bug is fixed, this starts failing to flag that
    /// `RequestServiceContext`'s doc comment (and the report) are stale and can be updated.
    @Test
    func dataTask_whenServiceContextSet_shouldBeObservedByTracerDuringExecution() async throws {
        try await withKnownIssue(
            "async-http-client loses ServiceContext.current across its internal EventLoop hop before starting the request span -- see TRACER_SERVICE_CONTEXT_REPORT.md"
        ) {
            try await Self.assertServiceContextObservedByTracer()
        }
    }

    private static func assertServiceContextObservedByTracer() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        var context = ServiceContext.topLevel
        context.testID = "trace-\(UUID().uuidString)"

        let tracer = ContextCapturingTracer()

        // A cold connection pool dispatches the first request onto the connection's own
        // EventLoop, off the calling Swift Task -- Swift's task-locals don't cross that hop, so
        // a warm-up request first (whose reply the test doesn't otherwise care about) gives the
        // pool an idle, already-established connection for the request that's actually asserted
        // on, keeping this deterministic instead of racing AsyncHTTPClient's own scheduling.
        _ = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer
                .tracer(tracer)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        // When
        _ = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session.localServer
                .tracer(tracer)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }

            RequestServiceContext(context)
        }
        .extractPayload()
        .result()

        // Then
        #expect(tracer.capturedTestID == context.testID)
    }
}

private final class ContextCapturingTracer: Tracer, Sendable {

    private let box = NIOLockedValueBox<String?>(nil)

    var capturedTestID: String? {
        box.withLockedValue { $0 }
    }

    func startSpan<Instant: TracerInstant>(
        _ operationName: String,
        context: @autoclosure () -> ServiceContext,
        ofKind kind: SpanKind,
        at instant: @autoclosure () -> Instant,
        function: String,
        file fileID: String,
        line: UInt
    ) -> NoOpTracer.NoOpSpan {
        let resolvedContext = context()
        box.withLockedValue { $0 = resolvedContext.testID }
        return NoOpTracer.NoOpSpan(context: resolvedContext)
    }

    func forceFlush() {}

    func inject<Carrier, Inject>(_ context: ServiceContext, into carrier: inout Carrier, using injector: Inject)
    where Inject: Injector, Carrier == Inject.Carrier {}

    func extract<Carrier, Extract>(_ carrier: Carrier, into context: inout ServiceContext, using extractor: Extract)
    where Extract: Extractor, Carrier == Extract.Carrier {}
}
