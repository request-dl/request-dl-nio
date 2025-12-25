/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A structure that represents an asynchronous response.
 */
public struct AsyncResponse: Sendable, AsyncSequence {

    /**
     A structure that defines an async iterator for the asynchronous response.
     */
    public struct Iterator: Sendable, AsyncIteratorProtocol {

        fileprivate let seed: Internals.TaskSeed
        fileprivate var iterator: Internals.AsyncResponse.Iterator

        /**
         Returns the next element in the sequence, or nil if there are no more elements.

         - Returns: The next element in the sequence.
         */
        mutating public func next() async throws -> Element? {
            switch try await iterator.next() {
            case .upload(let step):
                return .upload(UploadStep(
                    chunkSize: step.chunkSize,
                    totalSize: step.totalSize
                ))
            case .download(let step):
                return .download(DownloadStep(
                    head: .init(step.head),
                    bytes: AsyncBytes(
                        seed: seed,
                        bytes: step.bytes
                    )))
            case .none:
                return nil
            }
        }
    }

    public typealias Element = ResponseStep

    // MARK: - Internal properties

    var logger: Internals.TaskLogger? {
        response.logger
    }

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
