/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A structure that represents asynchronous bytes.
 */
public struct AsyncBytes: Sendable, AsyncSequence, Hashable {

    /**
     A structure that defines an async iterator for the asynchronous bytes.
     */
    public struct AsyncIterator: AsyncIteratorProtocol {

        fileprivate let seed: Internals.TaskSeed
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

    // MARK: - Public properties

    public var totalSize: Int {
        bytes.totalSize
    }

    // MARK: - Private properties

    private let seed: Internals.TaskSeed
    fileprivate let bytes: Internals.AsyncBytes

    // MARK: - Inits

    init(
        seed: Internals.TaskSeed,
        bytes: Internals.AsyncBytes
    ) {
        self.seed = seed
        self.bytes = bytes
    }

    // MARK: - Public methods

    /**
     Returns an async iterator over the elements of the sequence.

     - Returns: An async iterator for the asynchronous bytes.
     */
    public func makeAsyncIterator() -> AsyncIterator {
        .init(
            seed: seed,
            iterator: bytes.makeAsyncIterator()
        )
    }
}
