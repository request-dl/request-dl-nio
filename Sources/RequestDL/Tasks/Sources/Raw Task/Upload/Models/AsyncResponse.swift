/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct AsyncResponse: AsyncSequence {

    public typealias Element = Response

    private let asyncResponse: Internals.AsyncResponse

    init(_ asyncResponse: Internals.AsyncResponse) {
        self.asyncResponse = asyncResponse
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(iterator: asyncResponse.makeAsyncIterator())
    }
}

extension AsyncResponse {

    public struct Iterator: AsyncIteratorProtocol {

        var iterator: Internals.AsyncResponse.Iterator

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
