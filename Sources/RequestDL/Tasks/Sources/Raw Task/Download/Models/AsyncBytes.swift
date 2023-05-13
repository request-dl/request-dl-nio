/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A structure that represents asynchronous bytes.
 */
public struct AsyncBytes: AsyncSequence, Hashable {

    /**
     A structure that defines an async iterator for the asynchronous bytes.
     */
    public struct AsyncIterator: AsyncIteratorProtocol {

        fileprivate var iterator: Internals.AsyncBytes.AsyncIterator

        /**
         Returns the next element in the sequence, or nil if there are no more elements.

         - Returns: The next element in the sequence.
         */
        public mutating func next() async throws -> Data? {
            try await iterator.next()
        }
    }

    public typealias Element = Data

    // MARK: - Private properties

    fileprivate let asyncBytes: Internals.AsyncBytes

    // MARK: - Inits

    init(_ asyncBytes: Internals.AsyncBytes) {
        self.asyncBytes = asyncBytes
    }

    // MARK: - Public methods

    /**
     Returns an async iterator over the elements of the sequence.

     - Returns: An async iterator for the asynchronous bytes.
     */
    public func makeAsyncIterator() -> AsyncIterator {
        .init(iterator: asyncBytes.makeAsyncIterator())
    }
}

// MARK: - Data extensions

extension Data {

    init(_ asyncBytes: AsyncBytes) async throws {
        try await self.init(asyncBytes.asyncBytes)
    }
}
