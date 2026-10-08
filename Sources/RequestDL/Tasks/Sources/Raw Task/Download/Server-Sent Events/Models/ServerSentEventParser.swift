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

        for line in lines {
            if let event = process(line: String(decoding: line, as: UTF8.self)) {
                events.append(event)
            }
        }

        return events
    }

    private mutating func process(line: String) -> ServerSentEvent? {
        if line.isEmpty {
            return dispatch()
        }

        if line.hasPrefix(":") {
            return nil
        }

        let field: Substring
        let value: Substring

        if let colonIndex = line.firstIndex(of: ":") {
            field = line[line.startIndex..<colonIndex]

            var rawValue = line[line.index(after: colonIndex)...]
            if rawValue.first == " " {
                rawValue = rawValue.dropFirst()
            }
            value = rawValue
        } else {
            field = line[...]
            value = ""
        }

        switch field {
        case "event":
            pendingEventType = String(value)
        case "data":
            pendingDataLines.append(String(value))
        case "id":
            if !value.contains("\u{0000}") {
                lastEventId = String(value)
            }
        case "retry":
            if !value.isEmpty, value.allSatisfy(\.isASCII), value.allSatisfy(\.isNumber) {
                pendingRetry = Int(value)
            }
        default:
            break
        }

        return nil
    }

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
