import Foundation
import NIOConcurrencyHelpers
@preconcurrency import Logging
@testable import RequestDL

final class TestLogHandler: LogHandler, @unchecked Sendable {

    var logLevel: Logger.Level  {
        get { lock.withLock { _logLevel }}
        set { lock.withLock { _logLevel = newValue }}
    }

    var metadata: Logger.Metadata {
        get { lock.withLock { _metadata }}
        set { lock.withLock { _metadata = newValue }}
    }

    private let onLogRecord: @Sendable (LogRecord) -> Void

    private let lock = NIOLock()

    private var _metadata: Logger.Metadata
    private var _logLevel: Logger.Level = .trace

    fileprivate init(
        logLevel: Logger.Level,
        metadata: Logger.Metadata,
        onLogRecord: @escaping @Sendable (LogRecord) -> Void
    ) {
        self._logLevel = logLevel
        self._metadata = metadata
        self.onLogRecord = onLogRecord
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let mergedMetadata = self.metadata.merging(metadata ?? [:]) { $1 }
        let record = LogRecord(
            level: level,
            message: message,
            metadata: mergedMetadata,
            source: source,
            file: file,
            function: function,
            line: line
        )
        onLogRecord(record)
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { lock.withLock { _metadata[key] } }
        set { lock.withLock { _metadata[key] = newValue }}
    }

    // MARK: - Supporting Types

    struct LogRecord: Sendable, Equatable, CustomStringConvertible {

        let level: Logger.Level
        let message: Logger.Message
        let metadata: Logger.Metadata
        let source: String
        let file: String
        let function: String
        let line: UInt

        var description: String {
            """
            [\(level)] \(message) \
            (file: \(file.lastPathComponent), line: \(line), function: \(function)) \
            metadata: \(metadata)
            """
        }
    }
}

private extension String {
    var lastPathComponent: String {
        split(separator: "/").last.map(String.init) ?? self
    }
}

extension Logger {

    @discardableResult
    static func withTesting<Value: Sendable>(
        level: Logger.Level = .trace,
        metadata: Logger.Metadata = [:],
        recorded: @escaping @Sendable (TestLogHandler.LogRecord) -> Void,
        perform operation: () async throws -> Value
    ) async rethrows -> Value {
        var environment = RequestEnvironmentValues()
        environment.logger = .init(
            label: "RDL-Testing",
            factory: { _ in
                TestLogHandler(
                    logLevel: level,
                    metadata: metadata,
                    onLogRecord: recorded
                )
        })

        return try await RequestEnvironmentValues.$current.withValue(environment, operation: operation)
    }
}
