//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Cuts a stream of arbitrary chunks into items, one delimiter at a time, keeping at most one
/// unfinished item in memory.
///
/// Shared by `AsyncBytes.lines(maximumLength:)`, `AsyncBytes.items(separatedBy:maximumLength:)`
/// and the Server-Sent Events parser, so all of them cut at the same places and all of them can
/// stop an item that never ends.
struct ItemSplitter {

    // MARK: - Internal types

    enum Delimiter {

        /// `LF`, `CRLF` or a lone `CR`, whichever comes first. A `CR` at the very end of a chunk
        /// ends the line and swallows an `LF` that opens the next chunk.
        case lineBreak

        /// A non-empty byte sequence, which may arrive split across two chunks.
        case bytes([UInt8])
    }

    struct Output {

        /// The items that ended in this chunk, in order, without their delimiter.
        var items: [Data] = []

        /// Whether an item outgrew the maximum. Everything before it is in `items`; the splitter
        /// takes nothing more once this is `true`.
        var exceededMaximum = false
    }

    // MARK: - Private properties

    private let delimiter: Delimiter
    private let maximumLength: Int?

    private var buffer = Data()
    private var sawTrailingCR = false
    private var hasExceededMaximum = false

    // MARK: - Inits

    /// - Parameters:
    ///   - delimiter: Where items end. A byte sequence must not be empty.
    ///   - maximumLength: The most bytes one item may take, not counting its delimiter. `nil`
    ///   puts no limit on it.
    init(delimiter: Delimiter, maximumLength: Int?) {
        self.delimiter = delimiter
        self.maximumLength = maximumLength
    }

    // MARK: - Internal methods

    mutating func feed(_ chunk: Data) -> Output {
        var output = Output()

        guard !hasExceededMaximum else {
            output.exceededMaximum = true
            return output
        }

        var chunk = chunk

        if sawTrailingCR {
            sawTrailingCR = false

            if chunk.first == UInt8(ascii: "\n") {
                chunk = chunk.dropFirst()
            }
        }

        // Where to start looking for a delimiter in the buffer once the chunk is appended: bytes
        // before it were already looked at, and a delimiter that starts earlier would have been
        // found then, unless it needed bytes that had not arrived. Keeps the work for one item
        // linear in its length however many chunks it takes.
        let searchOffset = max(0, buffer.count - (delimiterLength - 1))
        buffer.append(chunk)

        let start = buffer.startIndex
        var itemStart = start
        var searchStart = buffer.index(start, offsetBy: searchOffset)

        while let (delimiterStart, delimiterEnd) = nextDelimiter(from: searchStart) {
            let length = buffer.distance(from: itemStart, to: delimiterStart)

            if let maximumLength, length > maximumLength {
                finishWithExceededMaximum(&output)
                return output
            }

            output.items.append(Data(buffer[itemStart..<delimiterStart]))

            itemStart = delimiterEnd
            searchStart = delimiterEnd
        }

        buffer.removeSubrange(start..<itemStart)

        // What is left holds no delimiter. When the delimiter is a byte sequence, its last bytes
        // may be the start of one, and they are not part of the item yet.
        let pending = buffer.count - (delimiterLength - 1)

        if let maximumLength, pending > maximumLength {
            finishWithExceededMaximum(&output)
        }

        return output
    }

    /// What the stream left unfinished when it ended: an item with no delimiter after it. Empty
    /// when nothing is left, so a stream that ends right after a delimiter has no extra item.
    mutating func finish() -> Output {
        var output = Output()

        guard !hasExceededMaximum else {
            output.exceededMaximum = true
            return output
        }

        guard !buffer.isEmpty else {
            return output
        }

        defer { buffer.removeAll() }

        // The last bytes held back as a possible delimiter are part of this item now.
        if let maximumLength, buffer.count > maximumLength {
            hasExceededMaximum = true
            output.exceededMaximum = true
            return output
        }

        output.items.append(buffer)
        return output
    }

    // MARK: - Private methods

    private var delimiterLength: Int {
        switch delimiter {
        case .lineBreak:
            return 1
        case .bytes(let bytes):
            return bytes.count
        }
    }

    private mutating func finishWithExceededMaximum(_ output: inout Output) {
        hasExceededMaximum = true
        output.exceededMaximum = true
        buffer.removeAll()
    }

    /// The first delimiter at or after `searchStart`: where it starts, and where the next item
    /// does.
    private mutating func nextDelimiter(from searchStart: Data.Index) -> (Data.Index, Data.Index)? {
        switch delimiter {
        case .lineBreak:
            guard
                let breakIndex = buffer[searchStart...].firstIndex(where: {
                    $0 == UInt8(ascii: "\r") || $0 == UInt8(ascii: "\n")
                })
            else {
                return nil
            }

            var next = buffer.index(after: breakIndex)

            if buffer[breakIndex] == UInt8(ascii: "\r") {
                if next < buffer.endIndex, buffer[next] == UInt8(ascii: "\n") {
                    next = buffer.index(after: next)
                } else if next == buffer.endIndex {
                    sawTrailingCR = true
                }
            }

            return (breakIndex, next)

        case .bytes(let bytes):
            guard let first = bytes.first, buffer.count >= bytes.count else {
                return nil
            }

            var index = searchStart
            let lastStart = buffer.index(buffer.endIndex, offsetBy: -bytes.count)

            while index <= lastStart {
                if buffer[index] == first,
                    buffer[index..<buffer.index(index, offsetBy: bytes.count)].elementsEqual(bytes)
                {
                    return (index, buffer.index(index, offsetBy: bytes.count))
                }

                index = buffer.index(after: index)
            }

            return nil
        }
    }
}
