//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension Internals {

    /// Whether `Internals.AsyncResponse` needs to decode the response body itself, resolved once
    /// per request by whichever `RequestExecutingClient` conformance built it: each transport
    /// has its own reason to land on `.skip` or `.dispatch`, but what happens with the answer
    /// (matching `Content-Encoding`, wrapping the byte stream) is the same either way, so it
    /// lives here, once, rather than duplicated per executor.
    ///
    /// - Important: `.skip` covers two different reasons that both resolve to "leave the bytes
    /// alone": decompression is `.disabled`, or every configured algorithm is one the transport
    /// already decoded natively.
    ///
    /// The second case matters specifically for `.urlSession`: CFNetwork decodes gzip/deflate/br
    /// transparently but does *not* strip `Content-Encoding` from the headers it hands back
    /// (confirmed empirically), so this can never be reduced to "dispatch whenever the header is
    /// present" without risking a second, corrupting decode pass over already-decoded bytes.
    package enum ManualDecompressionDispatch: Sendable {
        case skip

        /// - Parameter nativelyDecoded: Lowercased `Content-Encoding` values the transport has
        ///   *already* decoded before handing these bytes over, and which must therefore be
        ///   passed straight through rather than matched against `algorithms`.
        ///
        ///   Neither transport strips `Content-Encoding` after decoding natively, so the header
        ///   alone can't tell the two apart; this is the only thing that can. Empty for
        ///   `.urlSession`, which suppresses CFNetwork's transparent decoding outright whenever
        ///   it dispatches at all, and non-empty only for `.nio`'s mixed case, where
        ///   `NIOHTTPResponseDecompressor` handles the gzip/deflate half of a list while manual
        ///   dispatch handles the rest.
        case dispatch(
            algorithms: [any Internals.DecompressionAlgorithm],
            nativelyDecoded: Set<String>
        )

        /// The common case: nothing was decoded on the way in, so every configured algorithm is
        /// this package's to apply.
        package static func dispatch(
            algorithms: [any Internals.DecompressionAlgorithm]
        ) -> Self {
            .dispatch(algorithms: algorithms, nativelyDecoded: [])
        }
    }

    /// Internals-layer counterpart to `RequestDL.UnsupportedContentEncodingError`, caught where
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

    /// The stream to actually read the response body from: `source` itself for `.skip`, or
    /// whenever `Content-Encoding` is absent or `identity`; otherwise a stream that decodes
    /// through whichever configured algorithm matches it.
    ///
    /// - Throws: `Internals.UnsupportedContentEncodingError` when `Content-Encoding` matches none
    /// of the dispatch algorithms. This is only reachable in `.dispatch`, meaning this package has
    /// already taken over decoding for this request, so a server sending something it wasn't
    /// asked for is a real, reportable mismatch rather than something to silently pass through.
    package func resolvedStream(
        for head: Internals.ResponseHead,
        source: Internals.AsyncStream<Internals.DataBuffer>
    ) throws -> Internals.AsyncStream<Internals.DataBuffer> {
        guard case .dispatch(let algorithms, let nativelyDecoded) = self else {
            return source
        }

        // Every `Content-Encoding` field line, comma-split and joined into one list. RFC 9110
        // §5.2 makes several field lines of the same name exactly equivalent to one comma-joined
        // line, so a server is free to send either — and taking only `.first` of either shape
        // means a body compressed twice is decoded once and handed back still compressed, with
        // `Internals.CacheControl` storing those wrong bytes on the way past.
        //
        // `identity` is dropped rather than counted: it stands for "no transformation", so it
        // never changes what has to be undone.
        //
        // Trimming goes through the package's own `trimming(where:)`, not
        // `trimmingCharacters(in: .whitespaces)`: that needs `Foundation.CharacterSet`, which
        // this file has no import for. Same as `Internals.CacheControl.directives(_:)`.
        let encodings =
            head
            .headerValues(named: "Content-Encoding")
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimming(where: \.isWhitespace).lowercased() }
            .filter { !$0.isEmpty && $0 != "identity" }

        guard let normalized = encodings.first else {
            return source
        }

        // Stacked encodings have to be undone in reverse order, and the second layer's algorithm
        // can't be known to match anything configured. Decoding only the outermost would return
        // bytes that are still compressed while claiming they aren't, so this reports the
        // mismatch instead, the same way an unrecognised single encoding already does.
        guard encodings.count == 1 else {
            throw Internals.UnsupportedContentEncodingError(value: encodings.joined(separator: ", "))
        }

        // Already decoded on the way in; the transport simply didn't strip the header on its way
        // back out. Decoding again here is how a perfectly good response gets corrupted.
        guard !nativelyDecoded.contains(normalized) else {
            return source
        }

        guard
            let algorithm = algorithms.first(where: {
                $0.contentEncodingValue.lowercased() == normalized
            })
        else {
            throw Internals.UnsupportedContentEncodingError(value: normalized)
        }

        return Internals.AsyncStream.decompressing(source, using: algorithm)
    }
}

extension Internals.AsyncStream where Element == Internals.DataBuffer {

    /// Feeds every chunk `source` produces through a fresh decoder, one per response, forwarding
    /// whatever comes back. `[UInt8]` decoding chunks may be empty, and empty chunks are simply
    /// not forwarded, since a `DecompressorStream` is explicitly allowed to buffer internally and
    /// emit nothing for a given call.
    ///
    /// `finish()` runs once `source` ends, flushing whatever the decoder is still holding before
    /// this stream itself closes.
    fileprivate static func decompressing(
        _ source: Internals.AsyncStream<Internals.DataBuffer>,
        using algorithm: any Internals.DecompressionAlgorithm
    ) -> Internals.AsyncStream<Internals.DataBuffer> {
        // `.untilFirstIteration`, not the default `.unbounded`: `output` is read exactly once,
        // by the single downstream consumer this decompressed stream is built for, the same way
        // `Internals.DownloadBuffer.stream` is. `.unbounded` retains every chunk for the life of
        // the stream (see `ReplaySubject`'s own doc), which for a large compressed download (the
        // `.brotli` fallback under `.nio`, or any custom `Decompressor`) meant the entire
        // decompressed body stayed resident in memory even after being read, defeating the
        // point of streaming it in the first place.
        let output = Internals.AsyncStream<Internals.DataBuffer>(bufferingPolicy: .untilFirstIteration)

        _Concurrency.Task {
            do {
                var stream = try algorithm()

                for try await chunk in source {
                    var chunk = chunk
                    let data = await chunk.readData(chunk.readableBytes) ?? Data()
                    let decoded = try stream(decompressing: data)

                    if !decoded.isEmpty {
                        output.append(.success(await Internals.DataBuffer(decoded)))
                    }
                }

                let tail = try stream.finish()

                if !tail.isEmpty {
                    output.append(.success(await Internals.DataBuffer(tail)))
                }

                output.close()
            } catch {
                output.append(.failure(error))
            }
        }

        return output
    }
}
