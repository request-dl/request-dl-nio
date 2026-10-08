//
// See LICENSE for this package's licensing information.
//

extension AsyncBytes {

    /// Parses the byte stream as `text/event-stream` (Server-Sent Events) framing.
    ///
    /// ```swift
    /// let result = try await DownloadTask {
    ///     BaseURL("example.com")
    ///     Path("stream")
    /// }
    /// .result()
    ///
    /// for try await event in result.payload.events() {
    ///     print(event.event, event.data)
    /// }
    /// ```
    ///
    /// - Important: There is no limit on how long one line may grow. A source that never sends a
    /// line break keeps filling memory. Use ``events(maximumLineLength:)`` when the source is not
    /// trusted.
    ///
    /// - Returns: A ``ServerSentEvents`` sequence that yields one ``ServerSentEvent`` per frame.
    public func events() -> ServerSentEvents {
        .init(bytes: self)
    }

    /// Parses the byte stream as `text/event-stream` framing, failing on a line that grows too
    /// large.
    ///
    /// Works like ``events()``, and the sequence fails with ``AsyncBytesItemTooLargeError`` as
    /// soon as one line grows past `maximumLineLength` without ending. The events that came
    /// before it have already been delivered, and the frame the line belonged to is dropped.
    ///
    /// The limit is per line, so it bounds a `data:` field but not an event made of very many
    /// short lines.
    ///
    /// - Parameter maximumLineLength: The most bytes one line may take, not counting its line
    /// break. Must be greater than zero.
    /// - Returns: A ``ServerSentEvents`` sequence that yields one ``ServerSentEvent`` per frame.
    ///
    /// - Precondition: `maximumLineLength > 0`.
    public func events(maximumLineLength: Int) -> ServerSentEvents {
        precondition(
            maximumLineLength > 0,
            "AsyncBytes.events(maximumLineLength:) requires maximumLineLength > 0; \(maximumLineLength) fits no line."
        )

        return .init(bytes: self, maximumLineLength: maximumLineLength)
    }
}
