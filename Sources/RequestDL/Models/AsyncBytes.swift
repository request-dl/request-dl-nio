//
//  File.swift
//
//
//  Created by Brenno on 20/03/23.
//

import Foundation
import RequestDLInternals

public struct AsyncBytes: AsyncSequence {

    public typealias Element = RequestDLInternals.AsyncBytes.Element

    fileprivate let asyncBytes: RequestDLInternals.AsyncBytes

    init(_ asyncBytes: RequestDLInternals.AsyncBytes) {
        self.asyncBytes = asyncBytes
    }

    public func makeAsyncIterator() -> RequestDLInternals.AsyncBytes.AsyncIterator {
        asyncBytes.makeAsyncIterator()
    }
}

extension Data {

    init(_ asyncBytes: AsyncBytes) async throws {
        try await self.init(asyncBytes.asyncBytes)
    }
}
