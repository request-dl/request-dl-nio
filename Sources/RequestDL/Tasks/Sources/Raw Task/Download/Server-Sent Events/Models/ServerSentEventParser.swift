//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Incrementally decodes `text/event-stream` bytes into ``ServerSentEvent`` values.
///
/// Bytes are fed in arbitrary chunks via ``feed(_:)``: a chunk may end mid-line, and a line may even
/// be split across a `CR`/`LF` boundary between two chunks. State is kept internally so a caller never
/// has to reassemble lines itself.
struct ServerSentEventParser {

    // MARK: - Internal properties

    /// Whether a line outgrew the maximum. The events before it were returned by the `feed(_:)`
    /// that found it; the parser takes nothing more after that.
    private(set) var exceededMaximum = false

    // MARK: - Private properties

    private var splitter: ItemSplitter

    private var lastEventId: String?
    private var pendingEventType: String?
    private var pendingDataLines: [String] = []
    private var pendingRetry: Int?
    private var isAtStartOfStream = true

    // MARK: - Inits

    /// - Parameter maximumLineLength: The most bytes one line may take, not counting its line
    /// break. `nil` puts no limit on it.
    init(maximumLineLength: Int? = nil) {
        splitter = ItemSplitter(delimiter: .lineBreak, maximumLength: maximumLineLength)
    }

    // MARK: - Internal methods

    mutating func feed(_ chunk: Data) -> [ServerSentEvent] {
        let output = splitter.feed(chunk)
        exceededMaximum = exceededMaximum || output.exceededMaximum

        return events(from: output.items)
    }

    /// Flushes whatever the stream left buffered when it ended: a trailing line with no `CR`/`LF`
    /// terminator, and/or a frame that was never closed off by a final blank line. Real servers
    /// routinely close the connection right after the last event without emitting that blank line,
    /// so treating end-of-stream as an implicit frame boundary avoids silently dropping it.
    mutating func finish() -> ServerSentEvent? {
        let output = splitter.finish()
        exceededMaximum = exceededMaximum || output.exceededMaximum

        if let event = events(from: output.items).first {
            return event
        }

        // Nothing is dispatched for a frame that a line over the maximum cut short.
        return exceededMaximum ? nil : dispatch()
    }

    // MARK: - Private methods

    private mutating func events(from lines: [Data]) -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []

        for var line in lines {
            if isAtStartOfStream {
                isAtStartOfStream = false

                // A byte order mark opens the stream and is not part of the first line.
                if line.starts(with: Self.byteOrderMark) {
                    line = line.dropFirst(Self.byteOrderMark.count)
                }
            }

            if let event = process(line: line) {
                events.append(event)
            }
        }

        return events
    }

    /// Works on bytes, not characters: a `:` followed by a combining mark is one character, and
    /// would hide the colon and the space after it.
    private mutating func process(line: Data) -> ServerSentEvent? {
        guard let first = line.first else {
            return dispatch()
        }

        if first == Self.colon {
            return nil
        }

        let field: Data
        var value: Data

        if let colonIndex = line.firstIndex(of: Self.colon) {
            field = line[line.startIndex..<colonIndex]
            value = line[line.index(after: colonIndex)...]

            if value.first == Self.space {
                value = value.dropFirst()
            }
        } else {
            field = line
            value = Data()
        }

        switch String(decoding: field, as: UTF8.self) {
        case "event":
            pendingEventType = String(decoding: value, as: UTF8.self)
        case "data":
            pendingDataLines.append(String(decoding: value, as: UTF8.self))
        case "id":
            if !value.contains(0) {
                lastEventId = String(decoding: value, as: UTF8.self)
            }
        case "retry":
            if !value.isEmpty, value.allSatisfy({ (Self.zero...Self.nine).contains($0) }) {
                pendingRetry = Int(String(decoding: value, as: UTF8.self))
            }
        default:
            break
        }

        return nil
    }

    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let colon = UInt8(ascii: ":")
    private static let space = UInt8(ascii: " ")
    private static let zero = UInt8(ascii: "0")
    private static let nine = UInt8(ascii: "9")

    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            pendingEventType = nil
            pendingDataLines = []
        }

        guard !pendingDataLines.isEmpty else {
            return nil
        }

        return ServerSentEvent(
            id: lastEventId,
            event: pendingEventType ?? "message",
            data: pendingDataLines.joined(separator: "\n"),
            retry: pendingRetry
        )
    }
}
