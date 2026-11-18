//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import NIOCore
import NIOHTTP1
import NIOHTTPCompression

extension Internals {

    /// Keeps `NIOHTTPResponseDecompressor` from failing a message it was never given a byte of.
    ///
    /// That handler starts a decoder on any head that names `gzip` or `deflate`, and at the end of
    /// the message asks it to finish. A decoder that saw nothing says its stream was truncated, and
    /// the handler fires that as an error, ahead of the end itself. For a message with a body that
    /// is right; for one with no body there was nothing to truncate. `Internals.BodylessResponse`
    /// recognises the second case in the delegate, but only for the final response: a redirect
    /// with an encoding and no body (a `301` that copies the headers of what it moved, say) fails
    /// inside AsyncHTTPClient before the delegate sees a head it could tell it apart by, and the
    /// redirect it was following cannot be resumed from there.
    ///
    /// So the pipeline itself tells the two apart, and from what actually went into the
    /// decompressor, not from what the head says: an observer in front of it notes whether the
    /// message carried any body byte, and a filter behind it drops the decompressor's
    /// `truncatedData` when it did not. Every other error, and a truncation of a body that was
    /// there, goes through as before. The end of the message follows the dropped error anyway
    /// (the decompressor fires both), so the request completes, or the redirect is followed.
    ///
    /// Installed through AsyncHTTPClient's connection initializers (see
    /// `Internals.Session.Configuration.build(isCompatibleWithNetworkFramework:)`), which run once
    /// the connection's own handlers are in and before any request is written: on the connection
    /// for HTTP/1.1, and on each stream for HTTP/2, where the decompressor lives per stream.
    ///
    /// - Note: The same rule, in the decompressor itself, is what upstream would need
    /// (`swift-nio-extras`: throw `truncatedData` from `decodeLast` only once some input was
    /// processed). This is here until then.
    package enum NothingToDecode {

        /// Puts the observer and the filter around `channel`'s decompressor. Nothing happens when
        /// the pipeline has none (decompression is off for its client).
        package static func install(on channel: any Channel) -> EventLoopFuture<Void> {
            guard channel.eventLoop.inEventLoop else {
                return channel.eventLoop.submit {
                    try install(in: channel.pipeline.syncOperations)
                }
            }

            return channel.eventLoop.makeCompletedFuture {
                try install(in: channel.pipeline.syncOperations)
            }
        }

        /// The same, on the event loop of the pipeline.
        package static func install(in pipeline: ChannelPipeline.SynchronousOperations) throws {
            guard let decompressor = try? pipeline.handler(type: NIOHTTPResponseDecompressor.self) else {
                return
            }

            let input = Input()

            try pipeline.addHandler(InputObserver(input), position: .before(decompressor))
            try pipeline.addHandler(TruncationFilter(input), position: .after(decompressor))
        }
    }
}

extension Internals.NothingToDecode {

    /// Whether the message going through the decompressor right now has carried a body byte.
    /// Shared by the two handlers of one pipeline, so touched only on its event loop.
    final class Input {
        var hasBodyBytes = false
    }

    /// In front of the decompressor: sees what goes into it.
    final class InputObserver: ChannelInboundHandler {

        typealias InboundIn = HTTPClientResponsePart
        typealias InboundOut = HTTPClientResponsePart

        private let input: Input

        init(_ input: Input) {
            self.input = input
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            switch unwrapInboundIn(data) {
            case .head:
                input.hasBodyBytes = false
            case .body(let buffer):
                input.hasBodyBytes = input.hasBodyBytes || buffer.readableBytes > 0
            case .end:
                break
            }

            context.fireChannelRead(data)
        }
    }

    /// Behind the decompressor: drops its complaint about a message it was given nothing of.
    final class TruncationFilter: ChannelInboundHandler {

        typealias InboundIn = HTTPClientResponsePart
        typealias InboundOut = HTTPClientResponsePart

        private let input: Input

        init(_ input: Input) {
            self.input = input
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            context.fireChannelRead(data)
        }

        func errorCaught(context: ChannelHandlerContext, error: any Error) {
            let isTruncated = (error as? NIOHTTPDecompression.ExtraDecompressionError) == .truncatedData

            guard isTruncated, !input.hasBodyBytes else {
                context.fireErrorCaught(error)
                return
            }
        }
    }
}

@available(*, unavailable)
extension Internals.NothingToDecode.Input: Sendable {}

@available(*, unavailable)
extension Internals.NothingToDecode.InputObserver: Sendable {}

@available(*, unavailable)
extension Internals.NothingToDecode.TruncationFilter: Sendable {}

#endif
