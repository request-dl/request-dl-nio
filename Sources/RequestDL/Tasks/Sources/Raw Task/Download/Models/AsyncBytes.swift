/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct AsyncBytes: AsyncSequence {

    public typealias Element = Data

    fileprivate let asyncBytes: Internals.AsyncBytes

    init(_ asyncBytes: Internals.AsyncBytes) {
        self.asyncBytes = asyncBytes
    }

    public func makeAsyncIterator() -> AsyncIterator {
        .init(iterator: asyncBytes.makeAsyncIterator())
    }
}

extension AsyncBytes {

    public struct AsyncIterator: AsyncIteratorProtocol {

        fileprivate var iterator: Internals.AsyncBytes.AsyncIterator

        public mutating func next() async throws -> Data? {
            try await iterator.next()
        }
    }
}

extension Data {

    init(_ asyncBytes: AsyncBytes) async throws {
        try await self.init(asyncBytes.asyncBytes)
    }
}
