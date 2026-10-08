//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// An `AsyncSequence` that parses `text/event-stream` framing out of ``AsyncBytes``.
///
/// Bytes are consumed incrementally as they arrive over the network, so the response body is never
/// buffered in full: only the currently in-flight event frame is kept in memory.
public struct ServerSentEvents: Sendable, AsyncSequence {

    public typealias Element = ServerSentEvent

    ///
    /// A structure that defines an async iterator for the server-sent events.
    ///
    public struct AsyncIterator: AsyncIteratorProtocol {

        fileprivate let bytes: AsyncBytes
        fileprivate var bytesIterator: AsyncBytes.AsyncIterator
        fileprivate var parser: ServerSentEventParser
        fileprivate let maximumLineLength: Int?

        fileprivate var pendingEvents: [ServerSentEvent] = []
        fileprivate var pendingIndex = 0
        fileprivate var isFinished = false
        fileprivate var hasReportedFailure = false

        ///
        /// Returns the next event in the stream, or `nil` when the underlying byte stream ends.
        ///
        /// - Returns: The next ``ServerSentEvent``, if any.
        ///
        public mutating func next() async throws -> ServerSentEvent? {
            while true {
                if pendingIndex < pendingEvents.count {
                    defer { pendingIndex += 1 }
                    return pendingEvents[pendingIndex]
                }

                // After the events that came before the line, and also when the line was the
                // last thing the stream had.
                if parser.exceededMaximum, let maximumLineLength {
                    guard !hasReportedFailure else {
                        return nil
                    }

                    hasReportedFailure = true
                    isFinished = true
                    bytes.cancelTransfer()
                    throw AsyncBytesItemTooLargeError(maximumLength: maximumLineLength)
                }

                guard !isFinished else {
                    return nil
                }

                if let chunk = try await bytesIterator.next() {
                    pendingEvents = parser.feed(chunk)
                    pendingIndex = 0
                } else {
                    isFinished = true

                    if let event = parser.finish() {
                        pendingEvents = [event]
                        pendingIndex = 0
                    }
                }
            }
        }
    }

    // MARK: - Private properties

    private let bytes: AsyncBytes
    private let maximumLineLength: Int?

    // MARK: - Inits

    init(bytes: AsyncBytes, maximumLineLength: Int? = nil) {
        self.bytes = bytes
        self.maximumLineLength = maximumLineLength
    }

    // MARK: - Public methods

    ///
    /// Returns an async iterator over the parsed server-sent events.
    ///
    /// - Returns: An async iterator for the server-sent events.
    ///
    public func makeAsyncIterator() -> AsyncIterator {
        .init(
            bytes: bytes,
            bytesIterator: bytes.makeAsyncIterator(),
            parser: ServerSentEventParser(maximumLineLength: maximumLineLength),
            maximumLineLength: maximumLineLength
        )
    }
}
