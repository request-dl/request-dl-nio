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
    /// - Returns: A ``ServerSentEvents`` sequence that yields one ``ServerSentEvent`` per frame.
    public func events() -> ServerSentEvents {
        .init(bytes: self)
    }
}
