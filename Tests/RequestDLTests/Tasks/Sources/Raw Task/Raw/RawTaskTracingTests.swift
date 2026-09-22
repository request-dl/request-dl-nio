//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing
import Tracing

@testable import RequestDL

/// Covers `RawTask`'s span setup directly, against a recording tracer.
///
/// `.tracer(_:)` defaults to `NoOpTracer`, which discards every attribute set on it, so the only
/// other way to observe what actually lands on a span is a live request with a real tracer
/// configured. Driving `startRequestSpan` itself keeps these assertions about the attributes
/// rather than about the network.
struct RawTaskTracingTests {

    // MARK: - url.full redaction

    /// The regression: `url.full` used to carry `configuration.url` verbatim, which put the whole
    /// query string on the span and made `setURLAttributes`' deliberate omission of `url.query`
    /// pointless.
    @Test
    func startRequestSpan_whenURLHasQuery_omitsItFromURLFull() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"
        configuration.pathComponents = ["search"]
        configuration.queries = [
            QueryItem(name: "q", value: "swift"),
            QueryItem(name: "access_token", value: "s3cr3t-token-value")
        ]

        let tracer = SpanRecordingTracer()

        // When
        let span = RawTask<EmptyProperty>.startRequestSpan(tracer: tracer, configuration: &configuration)
        defer { span.end() }

        // Then
        let urlFull = try #require(tracer.stringAttribute("url.full"))

        #expect(!urlFull.contains("s3cr3t-token-value"))
        #expect(!urlFull.contains("access_token"))
        #expect(!urlFull.contains("?"))
        #expect(urlFull == "https://example.com/search")

        // The path is still worth having: it's the half that isn't secret-shaped.
        #expect(tracer.stringAttribute("url.path") == "/search")
    }

    /// Userinfo is credentials by definition, so it gets the same treatment as the query string.
    @Test
    func startRequestSpan_whenURLHasUserInfo_omitsItFromURLFull() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://alice:hunter2@example.com"
        configuration.pathComponents = ["profile"]

        let tracer = SpanRecordingTracer()

        // When
        let span = RawTask<EmptyProperty>.startRequestSpan(tracer: tracer, configuration: &configuration)
        defer { span.end() }

        // Then
        let urlFull = try #require(tracer.stringAttribute("url.full"))

        #expect(!urlFull.contains("hunter2"))
        #expect(!urlFull.contains("alice"))
        #expect(urlFull == "https://example.com/profile")
    }

    /// The ordinary case still carries the URL it always did; redaction isn't allowed to cost
    /// anything when there is nothing to redact.
    @Test
    func startRequestSpan_whenURLHasNoQueryOrUserInfo_carriesItUnchanged() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"
        configuration.pathComponents = ["users", "42"]

        let tracer = SpanRecordingTracer()

        // When
        let span = RawTask<EmptyProperty>.startRequestSpan(tracer: tracer, configuration: &configuration)
        defer { span.end() }

        // Then
        #expect(tracer.stringAttribute("url.full") == "https://example.com/users/42")
        #expect(tracer.stringAttribute("server.address") == "example.com")
    }
}

// MARK: - Test doubles

/// Records everything the one span it starts is given, and injects a fixed `traceparent` so the
/// header-propagation half is observable too.
private final class SpanRecordingTracer: Tracer, @unchecked Sendable {

    static let injectedTraceParent = "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"

    private let lock = NSLock()
    private var _span: RecordedSpan?

    var operationName: String? {
        lock.withLock { _span?.operationName }
    }

    func stringAttribute(_ key: String) -> String? {
        guard case .string(let value)? = lock.withLock({ _span?.attributes.get(key) }) else {
            return nil
        }

        return value
    }

    func startSpan<Instant: TracerInstant>(
        _ operationName: String,
        context: @autoclosure () -> ServiceContext,
        ofKind kind: SpanKind,
        at instant: @autoclosure () -> Instant,
        function: String,
        file fileID: String,
        line: UInt
    ) -> RecordedSpan {
        let span = RecordedSpan(operationName: operationName, context: context())
        lock.withLock { _span = span }
        return span
    }

    func forceFlush() {}

    func inject<Carrier, Inject>(_ context: ServiceContext, into carrier: inout Carrier, using injector: Inject)
    where Inject: Injector, Carrier == Inject.Carrier {
        injector.inject(Self.injectedTraceParent, forKey: "traceparent", into: &carrier)
    }

    func extract<Carrier, Extract>(_ carrier: Carrier, into context: inout ServiceContext, using extractor: Extract)
    where Extract: Extractor, Carrier == Extract.Carrier {}
}

private final class RecordedSpan: Tracing.Span, @unchecked Sendable {

    private let lock = NSLock()
    private var _operationName: String
    private var _attributes = SpanAttributes()

    let context: ServiceContext

    var operationName: String {
        get { lock.withLock { _operationName } }
        set { lock.withLock { _operationName = newValue } }
    }

    var attributes: SpanAttributes {
        get { lock.withLock { _attributes } }
        set { lock.withLock { _attributes = newValue } }
    }

    var isRecording: Bool { true }

    init(operationName: String, context: ServiceContext) {
        self._operationName = operationName
        self.context = context
    }

    func setStatus(_ status: SpanStatus) {}

    func addEvent(_ event: SpanEvent) {}

    func recordError<Instant: TracerInstant>(
        _ error: any Error,
        attributes: SpanAttributes,
        at instant: @autoclosure () -> Instant
    ) {}

    func addLink(_ link: SpanLink) {}

    func end<Instant: TracerInstant>(at instant: @autoclosure () -> Instant) {}
}
