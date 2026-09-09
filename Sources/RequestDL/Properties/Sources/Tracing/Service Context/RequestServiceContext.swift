//
// See LICENSE for this package's licensing information.
//

import Tracing

/// Binds a `ServiceContext` to a single request, overriding whatever `ServiceContext.current`
/// task-local happens to be ambient at the point the request executes.
///
/// RequestDL owns the whole distributed-tracing span lifecycle itself — starting the span, injecting
/// W3C trace headers, setting attributes, and ending it, all in `RawTask.result()` — rather than
/// handing `.tracer(_:)`'s tracer to `async-http-client`'s own `HTTPClient.Configuration.tracing
/// .tracer`. That built-in instrumentation only starts its span after hopping onto a SwiftNIO
/// `EventLoop`, which loses Swift's task-locals and makes it structurally unable to see a bound
/// `ServiceContext` — a confirmed upstream bug, reported against `async-http-client`. Doing it here
/// instead, one layer up and entirely within the caller's own task, means this binding has a real,
/// observable effect: it's what the started span picks up as its parent.
///
/// ```swift
/// DataTask {
///     BaseURL("example.com")
///     Session().tracer(myTracer)
///     RequestServiceContext(context)
/// }
/// ```
public struct RequestServiceContext: Property {

    private struct Node: PropertyNode {

        let context: ServiceContext

        func make(_ make: inout Make) async throws {
            make.requestConfiguration.serviceContext = context
        }
    }

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Internal properties

    let context: ServiceContext

    // MARK: - Inits

    ///
    /// Initializes a `RequestServiceContext` instance with the given context.
    ///
    /// - Parameter context: The `ServiceContext` to bind while this request executes.
    ///
    public init(_ context: ServiceContext) {
        self.context = context
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<RequestServiceContext>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            Node(context: property.context)
        )
    }
}
