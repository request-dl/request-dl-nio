//
// See LICENSE for this package's licensing information.
//

import Logging

@testable import RequestDL
@testable import RequestDLTestSupport

extension Logger {

    /// Builds a `Logger` backed by `TestLogHandler` and hands it directly to `operation` --
    /// the caller wires it into whichever `RequestTask` it's exercising via
    /// `.environment(\.logger, logger)`, since `RequestEnvironmentValues` no longer carries an
    /// ambient/task-local logger.
    @discardableResult
    static func withTesting<Value: Sendable>(
        level: Logger.Level = .trace,
        metadata: Logger.Metadata = [:],
        recorded: @escaping @Sendable (TestLogHandler.LogRecord) -> Void,
        perform operation: (Logger) async throws -> Value
    ) async rethrows -> Value {
        try await Logger.withTestHandler(
            level: level,
            metadata: metadata,
            recorded: recorded,
            perform: operation
        )
    }
}
