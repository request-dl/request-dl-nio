//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// The part of the iterators of ``AsyncBytesLines`` and ``AsyncBytesItems`` that is the same:
/// pull a chunk, cut it, hand the items out one at a time, and fail once an item is too large.
struct ItemIterator {

    // MARK: - Private properties

    private let bytes: AsyncBytes
    private var bytesIterator: AsyncBytes.AsyncIterator
    private var splitter: ItemSplitter
    private let maximumLength: Int?

    private var pending: [Data] = []
    private var pendingIndex = 0
    private var failure: AsyncBytesItemTooLargeError?
    private var isFinished = false

    // MARK: - Inits

    init(bytes: AsyncBytes, delimiter: ItemSplitter.Delimiter, maximumLength: Int?) {
        self.bytes = bytes
        self.bytesIterator = bytes.makeAsyncIterator()
        self.splitter = ItemSplitter(delimiter: delimiter, maximumLength: maximumLength)
        self.maximumLength = maximumLength
    }

    // MARK: - Internal methods

    mutating func next() async throws -> Data? {
        while true {
            if pendingIndex < pending.count {
                defer { pendingIndex += 1 }
                return pending[pendingIndex]
            }

            if let failure {
                self.failure = nil
                isFinished = true

                // Nothing will read the rest, and the caller may hold the bytes for a long
                // time yet: a source that sends an endless line would keep its connection.
                bytes.cancelTransfer()
                throw failure
            }

            guard !isFinished else {
                return nil
            }

            let output: ItemSplitter.Output

            if let chunk = try await bytesIterator.next() {
                output = splitter.feed(chunk)
            } else {
                isFinished = true
                output = splitter.finish()
            }

            pending = output.items
            pendingIndex = 0

            if output.exceededMaximum, let maximumLength {
                failure = AsyncBytesItemTooLargeError(maximumLength: maximumLength)
            }
        }
    }
}

/// An `AsyncSequence` of the lines of an ``AsyncBytes``, made by
/// ``AsyncBytes/lines(maximumLength:)``.
public struct AsyncBytesLines: Sendable, AsyncSequence {

    public typealias Element = String

    public struct AsyncIterator: AsyncIteratorProtocol {

        fileprivate var iterator: ItemIterator

        /// The next line, or `nil` when the byte stream ends.
        ///
        /// - Throws: ``AsyncBytesItemTooLargeError`` if a line outgrew the maximum, or the error
        /// that ended the byte stream.
        public mutating func next() async throws -> String? {
            try await iterator.next().map { String(decoding: $0, as: UTF8.self) }
        }
    }

    // MARK: - Private properties

    private let bytes: AsyncBytes
    private let maximumLength: Int

    // MARK: - Inits

    init(bytes: AsyncBytes, maximumLength: Int) {
        self.bytes = bytes
        self.maximumLength = maximumLength
    }

    // MARK: - Public methods

    public func makeAsyncIterator() -> AsyncIterator {
        .init(iterator: ItemIterator(bytes: bytes, delimiter: .lineBreak, maximumLength: maximumLength))
    }
}

/// An `AsyncSequence` of the items of an ``AsyncBytes`` between a separator, made by
/// ``AsyncBytes/items(separatedBy:maximumLength:)-([UInt8],_)``.
public struct AsyncBytesItems: Sendable, AsyncSequence {

    public typealias Element = Data

    public struct AsyncIterator: AsyncIteratorProtocol {

        fileprivate var iterator: ItemIterator

        /// The next item, without its separator, or `nil` when the byte stream ends.
        ///
        /// - Throws: ``AsyncBytesItemTooLargeError`` if an item outgrew the maximum, or the error
        /// that ended the byte stream.
        public mutating func next() async throws -> Data? {
            try await iterator.next()
        }
    }

    // MARK: - Private properties

    private let bytes: AsyncBytes
    private let separator: [UInt8]
    private let maximumLength: Int

    // MARK: - Inits

    init(bytes: AsyncBytes, separator: [UInt8], maximumLength: Int) {
        self.bytes = bytes
        self.separator = separator
        self.maximumLength = maximumLength
    }

    // MARK: - Public methods

    public func makeAsyncIterator() -> AsyncIterator {
        .init(iterator: ItemIterator(bytes: bytes, delimiter: .bytes(separator), maximumLength: maximumLength))
    }
}
