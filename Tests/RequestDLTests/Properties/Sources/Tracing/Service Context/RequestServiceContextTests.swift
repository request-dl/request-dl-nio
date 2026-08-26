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

    /// `async-http-client`'s own built-in tracing loses `ServiceContext.current` because it only
    /// starts its span after hopping onto a SwiftNIO `EventLoop` (full root cause in
    /// `TRACER_SERVICE_CONTEXT_REPORT.md`). RequestDL sidesteps that entirely by owning the span
    /// lifecycle itself, in `RawTask.result()`, entirely within the caller's own task -- no
    /// `EventLoop` hop involved -- so this now genuinely works, unlike when tracing was delegated to
    /// `async-http-client`.
    @Test
    func dataTask_whenServiceContextSet_shouldBeObservedByTracerDuringExecution() async throws {
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
