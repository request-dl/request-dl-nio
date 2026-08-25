//
// See LICENSE for this package's licensing information.
//

import Tracing

/// Binds a `ServiceContext` to a single request, overriding whatever `ServiceContext.current`
/// task-local happens to be ambient at the point the request executes.
///
/// - Warning: As of `async-http-client` 1.36.0, this currently has **no observable effect** on the
///   request `async-http-client` actually sends or on the span its configured `.tracer(_:)`
///   records. Confirmed empirically (see `RequestServiceContextTests.
///   dataTask_whenServiceContextSet_shouldBeObservedByTracerDuringExecution`), not merely
///   suspected: `async-http-client` starts the request's span only after execution hops onto a
///   SwiftNIO `EventLoop` via `EventLoop.execute(_:)` (`NIOLoopBound+Execute.swift`,
///   `RequestBag.willExecuteRequest`), and Swift's task-locals — which is what
///   `ServiceContext.current` is built on — do not cross that hop. This is a bug in
///   `async-http-client` itself, not something fixable from RequestDL's side; full root-cause
///   analysis and a suggested upstream fix are written up in `TRACER_SERVICE_CONTEXT_REPORT.md` at
///   the repository root.
///
///   This type, `RequestConfiguration.serviceContext`, and the bind around request execution in
///   `RawTask.result()` are kept in place — harmless today, and require no further RequestDL
///   changes to start working once the upstream bug is fixed.
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
