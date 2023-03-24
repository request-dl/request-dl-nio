//
//  File.swift
//
//
//  Created by Brenno on 20/03/23.
//

import Foundation
import RequestDLInternals

public struct AsyncResponse: AsyncSequence {

    public typealias Element = Response

    private let asyncResponse: RequestDLInternals.AsyncResponse

    init(_ asyncResponse: RequestDLInternals.AsyncResponse) {
        self.asyncResponse = asyncResponse
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(iterator: asyncResponse.makeAsyncIterator())
    }
}

extension AsyncResponse {

    public struct Iterator: AsyncIteratorProtocol {

        var iterator: RequestDLInternals.AsyncResponse.Iterator

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
