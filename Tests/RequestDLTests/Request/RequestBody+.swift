//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import Foundation
import NIOCore
import NIOPosix
import SwiftAsyncStream

@testable import RequestDL

extension RequestBody {

    func data() async throws -> Data {
        try await buffers().resolveData().reduce(Data(), +)
    }

    /// Drains the body by standing in for the HTTP client's stream writer.
    func buffers() async throws -> [Internals.DataBuffer] {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = group.any()

        let buffers = InlineProperty(wrappedValue: [Internals.DataBuffer]())

        try await build().stream(
            .init(closure: { ioData in
                switch ioData {
                case .byteBuffer(let byteBuffer):
                    // Empty writes carry no body bytes, so they are dropped.
                    //
                    // `RequestBody.connect` opens the stream with a zero length write. That is
                    // the only way to reach an `EventLoop` from inside `HTTPClient.Body.stream`,
                    // whose closure has to hand back a future synchronously and has nothing else
                    // to build one from. On the wire it is a no op, since the body is framed by
                    // `Content-Length` rather than chunked, and it has no business showing up
                    // here as a phantom chunk either.
                    guard byteBuffer.readableBytes > .zero else {
                        break
                    }

                    // Wrapped as a `ByteURL`, not read out through `readData(length:)`.
                    //
                    // Two reasons. `ByteBuffer.readData` belongs to `NIOFoundationCompat`, which
                    // this file does not import and which pulls in the whole of Foundation. And
                    // wrapping reaches `Internals.Buffer.init(_ url: Internals.ByteURL)`, the
                    // synchronous in-memory initializer, which is what lets this compile inside
                    // a synchronous NIO closure at all: the `Data` initializer is `async`.
                    //
                    // Same shape as `Internals.ClientResponseReceiver.didReceiveBodyPart`, and
                    // it copies nothing, since `ByteURL` takes a slice.
                    buffers.wrappedValue += [
                        Internals.DataBuffer(Internals.ByteURL(byteBuffer))
                    ]

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
            })
        ).get()

        try await group.shutdownGracefully()

        return buffers.wrappedValue
    }
}
