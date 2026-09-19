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

    // MARK: - Private properties

    private var lineBuffer = Data()
    /// How many leading bytes of `lineBuffer` have already been scanned for a line terminator
    /// and confirmed to have none, across every `extractLines(from:)` call since they arrived.
    ///
    /// Without this, `extractLines(from:)` searched from `lineBuffer.startIndex` on every call,
    /// re-scanning that same already-checked prefix each time a new chunk arrived with still no
    /// terminator in sight -- quadratic in the number of chunks making up one line, since each of
    /// N chunks re-scanned everything the previous N-1 already ruled out. A line built up over
    /// many small chunks (the default `ReadingMode` reads 1 KiB at a time) could peg a CPU core
    /// well before the line -- however long it eventually turns out to be -- ever completes.
    private var scannedPrefixLength = 0
    private var sawTrailingCR = false

    private var lastEventId: String?
    private var pendingEventType: String?
    private var pendingDataLines: [String] = []
    private var pendingRetry: Int?

    // MARK: - Internal methods

    mutating func feed(_ chunk: Data) -> [ServerSentEvent] {
        var events: [ServerSentEvent] = []

        for line in extractLines(from: chunk) {
            if let event = process(line: line) {
                events.append(event)
            }
        }

        return events
    }

    /// Flushes whatever the stream left buffered when it ended: a trailing line with no `CR`/`LF`
    /// terminator, and/or a frame that was never closed off by a final blank line. Real servers
    /// routinely close the connection right after the last event without emitting that blank line,
    /// so treating end-of-stream as an implicit frame boundary avoids silently dropping it.
    mutating func finish() -> ServerSentEvent? {
        if !lineBuffer.isEmpty {
            let line = String(decoding: lineBuffer, as: UTF8.self)
            lineBuffer.removeAll()
            scannedPrefixLength = 0

            if let event = process(line: line) {
                return event
            }
        }

        return dispatch()
    }

    // MARK: - Private methods

    private mutating func extractLines(from chunk: Data) -> [String] {
        var chunk = chunk

        if sawTrailingCR {
            sawTrailingCR = false

            if chunk.first == UInt8(ascii: "\n") {
                chunk = chunk.dropFirst()
            }
        }

        lineBuffer.append(chunk)

        var lines: [String] = []
        // Where the line currently being assembled starts -- always `lineBuffer.startIndex` at
        // the top of this call, since anything before that was already consumed as a complete
        // line (by this call or an earlier one) and removed below. Only advances when a
        // terminator is actually found.
        var lineStart = lineBuffer.startIndex
        // Where to resume *searching* for the next terminator -- distinct from `lineStart`
        // whenever the pending line spans more than one `feed(_:)` call: the bytes between
        // `lineStart` and here were already scanned (by an earlier call) and confirmed to hold
        // no terminator, so there is no need to look at them again, but they are still part of
        // the line's content once a terminator does turn up further along.
        var searchStart = lineBuffer.index(lineBuffer.startIndex, offsetBy: scannedPrefixLength)

        while let breakIndex = lineBuffer[searchStart...].firstIndex(where: {
            $0 == UInt8(ascii: "\r") || $0 == UInt8(ascii: "\n")
        }) {
            lines.append(String(decoding: lineBuffer[lineStart..<breakIndex], as: UTF8.self))

            var nextIndex = lineBuffer.index(after: breakIndex)

            if lineBuffer[breakIndex] == UInt8(ascii: "\r") {
                if nextIndex < lineBuffer.endIndex, lineBuffer[nextIndex] == UInt8(ascii: "\n") {
                    nextIndex = lineBuffer.index(after: nextIndex)
                } else if nextIndex == lineBuffer.endIndex {
                    sawTrailingCR = true
                }
            }

            lineStart = nextIndex
            searchStart = nextIndex
        }

        lineBuffer.removeSubrange(lineBuffer.startIndex..<lineStart)
        // Whatever remains was just confirmed, in the loop above, to hold no terminator anywhere
        // from `searchStart` (at the time this call began) through to the end -- so the next
        // call can resume searching exactly there instead of rechecking it.
        scannedPrefixLength = lineBuffer.count
        return lines
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
