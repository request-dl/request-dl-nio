//
// See LICENSE for this package's licensing information.
//

import Logging

@testable import RequestDL
@testable import RequestDLTestSupport

extension Logger {

    @discardableResult
    static func withTesting<Value: Sendable>(
        level: Logger.Level = .trace,
        metadata: Logger.Metadata = [:],
        recorded: @escaping @Sendable (TestLogHandler.LogRecord) -> Void,
        perform operation: () async throws -> Value
    ) async rethrows -> Value {
        try await Logger.withTestHandler(
            level: level,
            metadata: metadata,
            recorded: recorded
        ) { logger in
            var environment = RequestEnvironmentValues()
            environment.logger = logger

            return try await RequestEnvironmentValues.$current.withValue(environment, operation: operation)
        }
    }
}
