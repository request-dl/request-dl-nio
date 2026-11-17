//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import NIOCore
import NIOHTTP1
import NIOHTTPCompression

extension Internals {

    /// A response that cannot carry a body, and what `NIOHTTPResponseDecompressor` makes of one that
    /// still names a `Content-Encoding`.
    ///
    /// That handler starts decoding when the head says `gzip` or `deflate`, and at the end of the
    /// message asks its decoder to finish: one that was never given a byte reports its stream as
    /// truncated, and the request fails with it. A `HEAD` answered the way its `GET` would be (a
    /// CDN does exactly that), a `304` repeating the headers of the representation, a `204` and an
    /// empty body all say so on the head, and all of them are complete messages. Nothing was
    /// truncated: there was nothing to decode.
    ///
    /// The handler is part of the client's pipeline, and which pipeline a request travels is
    /// decided when its client is made, not per request, so this is recognised where the request
    /// ends and not where it starts.
    ///
    /// - Note: `Internals.NothingToDecode` now drops that complaint in the pipeline, before it
    /// reaches AsyncHTTPClient, which also covers a redirect (this only ever sees the final
    /// response). This stays as the delegate's own guard, for a pipeline it was not installed on.
    package struct BodylessResponse: Sendable {

        // MARK: - Private properties

        private let method: NIOHTTP1.HTTPMethod

        // MARK: - Inits

        package init(method: NIOHTTP1.HTTPMethod) {
            self.method = method
        }

        // MARK: - Internal methods

        /// Whether `head` is the head of a response that has no body, by what HTTP says (RFC 9110
        /// §6.4.1) and not by what the server happened to send.
        package func isBodyless(_ head: HTTPResponseHead) -> Bool {
            if method == .HEAD {
                return true
            }

            switch head.status.code {
            case 100..<200, 204, 304:
                return true
            default:
                return head.headers["Content-Length"].contains { $0.trimming(where: \.isWhitespace) == "0" }
            }
        }

        /// `transaction` as it should be reported for a response that ended with nothing to decode:
        /// the decompressor's complaint is not an error of the transaction. Delivered by
        /// AsyncHTTPClient before the error itself, so what says whether the response is the one that is
        /// about to be tolerated is what has been seen of it so far.
        package func reporting(
            _ transaction: Internals.TransactionMetrics,
            isBodylessResponse: Bool
        ) -> Internals.TransactionMetrics {
            guard isBodylessResponse, let error = transaction.error, isTruncatedDecoder(error) else {
                return transaction
            }

            var transaction = transaction
            transaction.error = nil
            return transaction
        }

        /// Whether `error` is the decompressor reporting, at the end of a message with no body, that
        /// it never saw one.
        package func isTruncatedDecoder(_ error: any Error) -> Bool {
            (error as? NIOHTTPDecompression.ExtraDecompressionError) == .truncatedData
        }
    }
}

#endif
