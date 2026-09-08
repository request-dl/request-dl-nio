//
// See LICENSE for this package's licensing information.
//

import NIOCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension Internals {

    /// Whether `Internals.AsyncResponse` needs to decode the response body itself, resolved once
    /// per request by whichever `RequestExecutingClient` conformance built it -- each transport
    /// has its own reason to land on `.skip` or `.dispatch`, but what happens with the answer
    /// (matching `Content-Encoding`, wrapping the byte stream) is the same either way, so it
    /// lives here, once, rather than duplicated per executor.
    ///
    /// - Important: `.skip` covers two different reasons that both resolve to "leave the bytes
    /// alone": decompression is `.disabled`, or every configured algorithm is one the transport
    /// already decoded natively. The second case matters specifically for `.urlSession` --
    /// CFNetwork decodes gzip/deflate/br transparently but does *not* strip `Content-Encoding`
    /// from the headers it hands back (confirmed empirically), so this can never be reduced to
    /// "dispatch whenever the header is present" without risking a second, corrupting decode
    /// pass over already-decoded bytes.
    package enum ManualDecompressionDispatch: Sendable {
        case skip
        case dispatch(algorithms: [any Internals.DecompressionAlgorithm])
    }

    /// Internals-layer counterpart to `RequestDL.UnsupportedContentEncodingError` -- caught where
    /// the public `AsyncResponse` wrapper turns an `Internals.AsyncResponse` into its own public
    /// types, and rewrapped there, following the same split `ExecutorRequirementError` uses for
    /// `Internals.IncompatibleExecutorConfigurationError`.
    package struct UnsupportedContentEncodingError: Error, Sendable {
        package let value: String

        package init(value: String) {
            self.value = value
        }
    }
}

extension Internals.ManualDecompressionDispatch {

    /// The stream to actually read the response body from -- `source` itself for `.skip`, or
    /// whenever `Content-Encoding` is absent or `identity`; otherwise a stream that decodes
    /// through whichever configured algorithm matches it.
    ///
    /// - Throws: `Internals.UnsupportedContentEncodingError` when `Content-Encoding` matches none
    /// of the dispatch algorithms -- only reachable in `.dispatch`, meaning this package has
    /// already taken over decoding for this request, so a server sending something it wasn't
    /// asked for is a real, reportable mismatch rather than something to silently pass through.
    package func resolvedStream(
        for head: Internals.ResponseHead,
        source: Internals.AsyncStream<Internals.DataBuffer>
    ) throws -> Internals.AsyncStream<Internals.DataBuffer> {
        guard case .dispatch(let algorithms) = self else {
            return source
        }

        guard
            let contentEncoding = head.headerValues(named: "Content-Encoding").first,
            contentEncoding.lowercased() != "identity"
        else {
            return source
        }

        guard
            let algorithm = algorithms.first(where: {
                $0.contentEncodingValue.lowercased() == contentEncoding.lowercased()
            })
        else {
            throw Internals.UnsupportedContentEncodingError(value: contentEncoding)
        }

        return Internals.AsyncStream.decompressing(source, using: algorithm)
    }
}

extension Internals.AsyncStream where Element == Internals.DataBuffer {

    /// Feeds every chunk `source` produces through a fresh decoder, one per response, forwarding
    /// whatever comes back -- `[UInt8]` decoding chunks may be empty, and empty chunks are simply
    /// not forwarded, since a `DecompressorStream` is explicitly allowed to buffer internally and
    /// emit nothing for a given call. `finish()` runs once `source` ends, flushing whatever the
    /// decoder is still holding before this stream itself closes.
    fileprivate static func decompressing(
        _ source: Internals.AsyncStream<Internals.DataBuffer>,
        using algorithm: any Internals.DecompressionAlgorithm
    ) -> Internals.AsyncStream<Internals.DataBuffer> {
        let output = Internals.AsyncStream<Internals.DataBuffer>()

        _Concurrency.Task {
            do {
                var stream = try algorithm()

                for try await chunk in source {
                    var chunk = chunk
                    let data = await chunk.readData(chunk.readableBytes) ?? Data()
                    let decoded = try stream.callAsFunction(decompressing: ByteBuffer(bytes: Array(data)))

                    if decoded.readableBytes > 0 {
                        output.append(.success(await Internals.DataBuffer(Data(decoded.readableBytesView))))
                    }
                }

                let tail = try stream.finish()

                if tail.readableBytes > 0 {
                    output.append(.success(await Internals.DataBuffer(Data(tail.readableBytesView))))
                }

                output.close()
            } catch {
                output.append(.failure(error))
            }
        }

        return output
    }
}
