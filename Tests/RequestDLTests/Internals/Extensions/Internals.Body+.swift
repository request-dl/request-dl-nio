/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import NIOPosix
import AsyncHTTPClient
@testable import RequestDL

extension Internals.Body {

    func data() async throws -> Data {
        try await buffers().resolveData().reduce(Data(), +)
    }

    func buffers() async throws -> [Internals.DataBuffer] {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = group.any()

        let buffers = SendableBox([Internals.DataBuffer]())

        try await build().stream(.init(closure: {
            switch $0 {
            case .byteBuffer(var byteBuffer):
                if let data = byteBuffer.readData(length: byteBuffer.readableBytes) {
                    buffers(buffers() + [.init(data)])
                }
            case .fileRegion:
                Internals.preconditionFailure(
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

        try await group.shutdownGracefully()

        return buffers()
    }
}
