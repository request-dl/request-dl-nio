//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension AsyncBytes {

    /// Reads the byte stream line by line.
    ///
    /// ```swift
    /// let result = try await DownloadTask {
    ///     BaseURL("example.com")
    ///     Path("stream.ndjson")
    /// }
    /// .result()
    ///
    /// for try await line in result.payload.lines() {
    ///     print(line)
    /// }
    /// ```
    ///
    /// A line ends at `LF`, `CRLF` or a lone `CR`, including when the two bytes of `CRLF` arrive
    /// in different chunks. An empty line is delivered as an empty string, and a last line with
    /// no line break after it is delivered when the stream ends. Bytes are decoded as UTF-8, and
    /// an invalid sequence becomes U+FFFD.
    ///
    /// The lines are cut as the consumer asks for them, so a slow consumer slows the download
    /// down through the usual back pressure instead of letting lines pile up. Only the line being
    /// read is kept in memory, and the sequence fails with ``AsyncBytesItemTooLargeError`` as
    /// soon as it grows past `maximumLength`, so a source that never sends a line break cannot
    /// fill memory.
    ///
    /// - Parameter maximumLength: The most bytes one line may take, not counting its line break.
    /// The default of 1 MiB is generous for text protocols. Must be greater than zero.
    /// - Returns: An ``AsyncBytesLines`` sequence that yields one `String` per line.
    ///
    /// - Precondition: `maximumLength > 0`.
    public func lines(maximumLength: Int = 1_048_576) -> AsyncBytesLines {
        precondition(
            maximumLength > 0,
            "AsyncBytes.lines(maximumLength:) requires maximumLength > 0; \(maximumLength) fits no line."
        )

        return AsyncBytesLines(bytes: self, maximumLength: maximumLength)
    }

    /// Reads the byte stream as items between a separator.
    ///
    /// Works like ``lines(maximumLength:)`` for any non-empty byte separator, such as `0x1E`
    /// (record separator) or `"\n\n"`. The separator is not part of the items, and it may arrive
    /// split across chunks. Two separators in a row give an empty item, and the last item is
    /// delivered when the stream ends even without a separator after it.
    ///
    /// - Parameters:
    ///   - separator: The bytes that end an item. Must not be empty.
    ///   - maximumLength: The most bytes one item may take, not counting the separator. Must be
    ///   greater than zero.
    /// - Returns: An ``AsyncBytesItems`` sequence that yields one `Data` per item.
    ///
    /// - Precondition: `separator` is not empty and `maximumLength > 0`.
    public func items(separatedBy separator: [UInt8], maximumLength: Int = 1_048_576) -> AsyncBytesItems {
        precondition(!separator.isEmpty, "AsyncBytes.items(separatedBy:maximumLength:) requires a separator.")
        precondition(
            maximumLength > 0,
            "AsyncBytes.items(separatedBy:maximumLength:) requires maximumLength > 0; \(maximumLength) fits no item."
        )

        return AsyncBytesItems(bytes: self, separator: separator, maximumLength: maximumLength)
    }

    /// Reads the byte stream as items between a separator written as text.
    ///
    /// See ``items(separatedBy:maximumLength:)``; the separator is taken as UTF-8.
    public func items<S: StringProtocol>(separatedBy separator: S, maximumLength: Int = 1_048_576) -> AsyncBytesItems {
        items(separatedBy: Array(separator.utf8), maximumLength: maximumLength)
    }
}
