/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A structure that represents an asynchronous response.
 */
public struct AsyncResponse: AsyncSequence {

    /// The type of the elements in the asynchronous sequence.
    public typealias Element = Response

    private let asyncResponse: Internals.AsyncResponse

    init(_ asyncResponse: Internals.AsyncResponse) {
        self.asyncResponse = asyncResponse
    }

    /**
     Returns an async iterator over the elements of the sequence.

     - Returns: An async iterator for the asynchronous response.
     */
    public func makeAsyncIterator() -> Iterator {
        Iterator(iterator: asyncResponse.makeAsyncIterator())
    }
}

extension AsyncResponse {

    /**
     A structure that defines an async iterator for the asynchronous response.
     */
    public struct Iterator: AsyncIteratorProtocol {

        var iterator: Internals.AsyncResponse.Iterator

        /**
         Returns the next element in the sequence, or nil if there are no more elements.

         - Returns: The next element in the sequence.
         */
        mutating public func next() async throws -> Element? {
            switch try await iterator.next() {
            case .upload(let part):
                return .upload(part)
            case .download(let head, let bytes):
                return .download(.init(head), .init(bytes))
            case .none:
                return nil
            }
        }
    }
}
