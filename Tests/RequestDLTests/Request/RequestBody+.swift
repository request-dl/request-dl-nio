//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import NIOPosix
import SwiftAsyncStream

@testable import RequestDL
import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension RequestBody {

    func data() async throws -> Data {
        try await buffers().resolveData().reduce(Data(), +)
    }

    /// Drains the body by standing in for the HTTP client's stream writer.
    func buffers() async throws -> [Internals.DataBuffer] {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let eventLoop = group.any()

        let buffers = InlineProperty(wrappedValue: [Internals.DataBuffer]())

        try await build(eventLoop: eventLoop).stream(
            .init(closure: { ioData in
                switch ioData {
                case .byteBuffer(let byteBuffer):
                    // Wrapped as a `ByteURL`, not read out through `readData(length:)`.
                    //
                    // Two reasons, and both are why `.init(data)` cannot stay here. That spelling
                    // resolves to `Internals.Buffer.init(_ data: some DataProtocol) async`, and
                    // this closure is synchronous; wrapping reaches
                    // `Internals.Buffer.init(_ url: Internals.ByteURL)`, the synchronous
                    // in-memory initializer, which exists precisely because that path never
                    // suspends.
                    //
                    // And `ByteBuffer.readData(length:)` belongs to `NIOFoundationCompat`, which
                    // this file does not import and which pulls in the whole of Foundation.
                    //
                    // Same shape as `Internals.ClientResponseReceiver.didReceiveBodyPart`, and it
                    // copies nothing, since `ByteURL` takes a slice.
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
