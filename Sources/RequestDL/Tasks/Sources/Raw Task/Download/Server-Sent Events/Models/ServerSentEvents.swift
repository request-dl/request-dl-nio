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
/// buffered in full -- only the currently in-flight event frame is kept in memory.
public struct ServerSentEvents: Sendable, AsyncSequence {

    public typealias Element = ServerSentEvent

    ///
    /// A structure that defines an async iterator for the server-sent events.
    ///
    public struct AsyncIterator: AsyncIteratorProtocol {

        fileprivate var bytesIterator: AsyncBytes.AsyncIterator
        fileprivate var parser = ServerSentEventParser()

        fileprivate var pendingEvents: [ServerSentEvent] = []
        fileprivate var pendingIndex = 0
        fileprivate var isFinished = false

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

    // MARK: - Inits

    init(bytes: AsyncBytes) {
        self.bytes = bytes
    }

    // MARK: - Public methods

    ///
    /// Returns an async iterator over the parsed server-sent events.
    ///
    /// - Returns: An async iterator for the server-sent events.
    ///
    public func makeAsyncIterator() -> AsyncIterator {
        .init(bytesIterator: bytes.makeAsyncIterator())
    }
}
