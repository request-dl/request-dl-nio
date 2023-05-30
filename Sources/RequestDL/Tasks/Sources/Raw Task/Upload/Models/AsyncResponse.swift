/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A structure that represents an asynchronous response.
 */
public struct AsyncResponse: AsyncSequence {

    /**
     A structure that defines an async iterator for the asynchronous response.
     */
    public struct Iterator: AsyncIteratorProtocol {

        fileprivate let seed: Internals.TaskSeed
        fileprivate var iterator: Internals.AsyncResponse.Iterator

        /**
         Returns the next element in the sequence, or nil if there are no more elements.

         - Returns: The next element in the sequence.
         */
        mutating public func next() async throws -> Element? {
            switch try await iterator.next() {
            case .upload(let part):
                return .upload(part)
            case .download(let head, let bytes):
                return .download(.init(head), .init(
                    seed: seed,
                    bytes: bytes
                ))
            case .none:
                return nil
            }
        }
    }

    public typealias Element = Response

    // MARK: - Private properties

    private let seed: Internals.TaskSeed
    private let response: Internals.AsyncResponse

    // MARK: - Inits

    init(
        seed: Internals.TaskSeed,
        response: Internals.AsyncResponse
    ) {
        self.seed = seed
        self.response = response
    }

    // MARK: - Public methods

    /**
     Returns an async iterator over the elements of the sequence.

     - Returns: An async iterator for the asynchronous response.
     */
    public func makeAsyncIterator() -> Iterator {
        Iterator(
            seed: seed,
            iterator: response.makeAsyncIterator()
        )
    }
}
