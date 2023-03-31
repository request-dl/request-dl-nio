/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import NIOPosix
import AsyncHTTPClient

extension RequestBody {

    func data() async throws -> Data {
        try await buffers().resolveData().reduce(Data(), +)
    }

    func buffers() async throws -> [DataBuffer] {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = group.any()

        var buffers: [DataBuffer] = []

        try await build().stream(.init(closure: {
            switch $0 {
            case .byteBuffer(var byteBuffer):
                if let data = byteBuffer.readData(length: byteBuffer.readableBytes) {
                    buffers.append(.init(data))
                }
            case .fileRegion:
                Log.failure(
                    """
                    RequestBody currently doesn't support stream using \
                    IOData.fileRegion.

                    This was an unexpected behavior.

                    Please, open a bug report 🔎
                    """
                )
            }

            return eventLoop.makeSucceededVoidFuture()
        })).get()

        return buffers
    }
}
