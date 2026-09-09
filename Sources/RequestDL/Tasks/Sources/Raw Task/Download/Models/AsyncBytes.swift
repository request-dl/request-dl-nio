//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// A structure that represents asynchronous bytes.
public struct AsyncBytes: Sendable, AsyncSequence, Hashable {

    ///
    /// A structure that defines an async iterator for the asynchronous bytes.
    ///
    public struct AsyncIterator: AsyncIteratorProtocol {

        fileprivate let seed: Internals.TaskSeed
        fileprivate var iterator: Internals.AsyncBytes.AsyncIterator
        fileprivate let deadline: Internals.ResourceDeadline

        ///
        /// Returns the next element in the sequence, or nil if there are no more elements.
        ///
        /// - Returns: The next element in the sequence.
        ///
        public mutating func next() async throws -> Data? {
            // See `AsyncResponse.Iterator.next()` for why `iterator` is captured immutably here
            // and re-assigned afterward, rather than mutated directly inside the raced closure.
            let startIterator = iterator
            do {
                let (element, updatedIterator) = try await deadline.race(seed: seed) {
                    var iterator = startIterator
                    let element = try await iterator.next()
                    return (element, iterator)
                }
                iterator = updatedIterator
                return element
            } catch is Internals.ResourceTimeoutError {
                throw ResourceTimeoutError()
            }
        }
    }

    public typealias Element = Data

    // MARK: - Public properties

    ///
    /// The total size of the response body.
    ///
    /// Internally, the value is known when the client receives the response head which contains the
    /// `Content-Length` header.
    ///
    public var totalSize: Int {
        bytes.totalSize
    }

    // MARK: - Internal properties

    var logger: Internals.TaskLogger? {
        bytes.logger
    }

    // MARK: - Private properties

    private let seed: Internals.TaskSeed
    fileprivate let bytes: Internals.AsyncBytes
    private let deadline: Internals.ResourceDeadline

    // MARK: - Inits

    init(
        seed: Internals.TaskSeed,
        bytes: Internals.AsyncBytes,
        deadline: Internals.ResourceDeadline = .init(nanoseconds: nil)
    ) {
        self.seed = seed
        self.bytes = bytes
        self.deadline = deadline
    }

    // MARK: - Public methods

    ///
    /// Returns an async iterator over the elements of the sequence.
    ///
    /// - Returns: An async iterator for the asynchronous bytes.
    ///
    public func makeAsyncIterator() -> AsyncIterator {
        .init(
            seed: seed,
            iterator: bytes.makeAsyncIterator(),
            deadline: deadline
        )
    }
}

// MARK: - Equatable, Hashable

extension AsyncBytes {

    // `deadline` deliberately left out -- it's incidental race metadata, not part of what
    // identifies one `AsyncBytes` stream, the same way it was identified by `seed`/`bytes` alone
    // before `.resource` timeouts existed.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.seed == rhs.seed && lhs.bytes == rhs.bytes
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(seed)
        hasher.combine(bytes)
    }
}
