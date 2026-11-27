//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension BackgroundDownloads.Session {

    /// How much of the downloaded file is read, and so held in memory, at a time.
    private static let decodingChunkSize = 64 * 1024

    /// Decodes the file `URLSession` downloaded, when the request took over `Accept-Encoding` and
    /// the server answered with an encoding.
    ///
    /// Taking over `Accept-Encoding` is what makes this necessary: the server is asked for the
    /// encodings of the app's own decompressors, so the file at `location` is still encoded in
    /// them. (CFNetwork decodes gzip, deflate and brotli whatever `Accept-Encoding` says, and keeps
    /// the header: such a file is plain, and is not decoded here.) The decoded
    /// bytes are written next to `destination`, so that moving them there is a rename and not a
    /// copy across volumes, in `decodingChunkSize` pieces: the file is never held whole, which is
    /// the reason to stream a download to disk in the first place.
    ///
    /// - Returns: The decoded file, which the caller moves to `destination`, and the directory it
    ///   is in, which the caller removes whether or not that worked; `nil` when `location` is
    ///   already what has to be moved: the request did not take over `Accept-Encoding` (the common
    ///   case, and every download an older version scheduled), or the response carries no encoding
    ///   to undo.
    /// - Throws: ``UnsupportedContentEncodingError`` when the encoding is none of those the
    ///   request asked for, or several are stacked; ``BackgroundDownloadMissingDecompressorError``
    ///   when it is one that was asked for but no decompressor for it exists in this process; or
    ///   whatever the decompressor throws, a truncated or corrupt body included.
    func decodedFile(
        from location: URL,
        response: URLResponse?,
        task: URLSessionTask,
        destination: URL
    ) throws -> (file: URL, directory: URL)? {
        guard let accepted = Self.decodeAcceptedEncodings(task.taskDescription) else {
            return nil
        }

        let encodings = Self.contentEncodings(of: response)

        guard let encoding = encodings.first else {
            return nil
        }

        // Stacked encodings are undone in reverse, by algorithms nobody can tell are configured;
        // decoding only the outermost would claim plain bytes that still are not. The same answer
        // `Internals.ManualDecompressionDispatch` gives the foreground tasks.
        guard encodings.count == 1 else {
            throw UnsupportedContentEncodingError(value: encodings.joined(separator: ", "))
        }

        // Only what the request asked for: an encoding it did not ask for is the server's own doing,
        // and reported as such even when the app happens to have registered a decompressor for it,
        // as the foreground tasks do.
        guard accepted.contains(encoding) else {
            throw UnsupportedContentEncodingError(value: encoding)
        }

        // Asked for, and one the system decodes whoever's decompressor is registered under that
        // name (an app's own for `br`, say): CFNetwork decoded it, and kept the header. The file
        // is plain already, and running the decompressor over it would corrupt it or fail. Same
        // answer as the foreground `.urlSession` tasks.
        if Internals.Decompression.urlSessionNativeEncodings.contains(encoding) {
            return nil
        }

        guard let algorithm = decompressor(forEncoding: encoding, task: task) else {
            throw BackgroundDownloadMissingDecompressorError(contentEncoding: encoding)
        }

        // The system's own place for what is about to replace a file: on the same volume as
        // `destination`, so that moving it there is a rename and not a copy, and one the system
        // sweeps if the app is killed mid-decode, which a file left beside `destination` would
        // never be.
        let directory = try replacementDirectory(destination)
        let output = directory.appendingPathComponent(destination.lastPathComponent)

        guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
            try? FileManager.default.removeItem(at: directory)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: output.path])
        }

        do {
            try Self.decode(
                from: location,
                to: output,
                using: algorithm,
                limit: Self.decodeDecompressionLimit(task.taskDescription)
            )
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        return (output, directory)
    }

    /// The system's own place for what is about to replace `destination`, as
    /// ``decodedFile(from:response:task:destination:)`` uses it: a new directory on the same volume.
    static let systemReplacementDirectory: @Sendable (URL) throws -> URL = { destination in
        try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destination,
            create: true
        )
    }

    /// The pure part of ``decodedFile(from:response:task:destination:)``, kept apart so it can be
    /// tested without a download. `chunkSize` is a parameter only for the tests, to put the
    /// boundary between two reads where a decoder's own unit of input is cut in half.
    ///
    /// - Parameter limit: What the session that scheduled the download set with
    ///   ``Session/decompressionAlgorithms(_:limit:)``, checked after every piece against what has
    ///   been read and what has been written. ``Internals/Decompression/Limit/none``, the default
    ///   of that method, checks nothing: a custom algorithm is its own to bound unless the session
    ///   says so. This decoding runs inside a delegate callback of the system's own queue and writes
    ///   to the user's disk, which is why a limit that was set holds here too, and not only for the
    ///   native decoding it was written for.
    /// - Throws: ``BackgroundDownloadDecompressionLimitError`` when the limit is passed, with
    ///   whatever was written left for the caller to remove. A decoder that expands a single piece
    ///   past it still holds that piece whole in memory until it returns.
    static func decode(
        from input: URL,
        to output: URL,
        using algorithm: any Internals.DecompressionAlgorithm,
        limit: Internals.Decompression.Limit = .none,
        chunkSize: Int = decodingChunkSize
    ) throws {
        let reader = try FileHandle(forReadingFrom: input)
        defer { try? reader.close() }

        let writer = try FileHandle(forWritingTo: output)
        defer { try? writer.close() }

        var stream = try algorithm()
        var hasInput = false
        // Not `Int`: on a 32-bit platform (watchOS' `arm64_32`) an encoded file or an expansion
        // past 2 GiB overflows it, which traps the process instead of being a limit to report.
        var read: UInt64 = 0
        var written: UInt64 = 0

        while let chunk = try reader.read(upToCount: chunkSize), !chunk.isEmpty {
            hasInput = true
            read += UInt64(chunk.count)

            let decoded = try stream(decompressing: chunk)
            if !decoded.isEmpty {
                written += UInt64(decoded.count)
                try Self.enforce(limit, read: read, written: written)
                try writer.write(contentsOf: decoded)
            }
        }

        // A body without a byte is no stream to finish: a decoder asked for the end of something it
        // never began reports it as truncated. Same as the foreground decoding.
        if hasInput {
            let tail = try stream.finish()
            if !tail.isEmpty {
                written += UInt64(tail.count)
                try Self.enforce(limit, read: read, written: written)
                try writer.write(contentsOf: tail)
            }
        }

        try writer.synchronize()
    }

    /// Throws when `written` bytes of decoded output, from `read` bytes of input, pass `limit`.
    /// Checked before the bytes that pass it are written.
    ///
    /// Counted in `UInt64`: a count that passes `Int.max` on a 32-bit platform is a limit to
    /// report, not an overflow. A limit below zero is passed by any output at all, as it always
    /// was.
    static func enforce(_ limit: Internals.Decompression.Limit, read: UInt64, written: UInt64) throws {
        switch limit {
        case .none:
            return

        case .size(let maximum):
            if maximum < 0 || written > UInt64(maximum) {
                throw BackgroundDownloadDecompressionLimitError(limit: .size(maximum))
            }

        case .ratio(let maximum):
            guard maximum >= 0 else {
                throw BackgroundDownloadDecompressionLimitError(limit: .ratio(maximum))
            }

            let (allowed, overflow) = read.multipliedReportingOverflow(by: UInt64(maximum))
            if !overflow, written > allowed {
                throw BackgroundDownloadDecompressionLimitError(limit: .ratio(maximum))
            }
        }
    }

    /// What a request that takes over `Accept-Encoding` is for: the algorithms to decode with,
    /// set on `request` as the `Accept-Encoding` it sends, or `nil` and `request` untouched when
    /// the system does the decoding. The same rule the foreground `.urlSession` executor follows:
    /// CFNetwork decodes gzip, deflate and brotli on its own, and the only way to hand it anything
    /// else is to take over `Accept-Encoding`.
    ///
    /// Not for `.disabled`, which keeps what a background download has always done: the system
    /// decides.
    ///
    /// - Throws: ``BackgroundDownloadUnsupportedConfigurationError`` when the list that takes over
    ///   `Accept-Encoding` also holds an algorithm that only stands for the system's decoding
    ///   (`GzipAlgorithm`, `DeflateAlgorithm`, `BrotliURLSessionOnlyAlgorithm`). The request does
    ///   not ask for them, so such a response would fail when the download is done, which is too
    ///   late to be told.
    static func takingOverAcceptEncoding(
        of request: inout URLRequest,
        for decompression: Internals.Decompression
    ) throws -> [any Internals.DecompressionAlgorithm]? {
        guard case .enabled(let algorithms, _) = decompression, decompression.requiresManualURLSessionHandling else {
            return nil
        }

        guard !algorithms.contains(where: \.isNativelyDecodedByURLSession) else {
            throw BackgroundDownloadUnsupportedConfigurationError(reason: .nativeAlgorithmNextToCustomAlgorithm)
        }

        request.setValue(decompression.acceptEncoding, forHTTPHeaderField: "Accept-Encoding")
        return algorithms
    }

    /// The limit ``Session/decompressionAlgorithms(_:limit:)`` set in `decompression`, which is
    /// what bounds the decoding of the file a download that took over `Accept-Encoding` brings.
    static func limit(of decompression: Internals.Decompression) -> Internals.Decompression.Limit {
        guard case .enabled(_, let limit) = decompression else {
            return .none
        }

        return limit
    }

    /// What decodes a download continued from resume data. What goes on the wire is what the
    /// request that stopped sent, and that is what decides, not `content` written again: a
    /// download scheduled before this existed, or by a `content` that left decoding to the system,
    /// has no `Accept-Encoding` of its own, and was decoded by CFNetwork, so decoding it again
    /// would fail on what is already plain.
    ///
    /// `request` is `nil` when the system does not give the resumed task one, which says nothing
    /// either way, so `decompression` stands.
    static func decompression(
        _ decompression: [any Internals.DecompressionAlgorithm]?,
        resumedFrom request: URLRequest?
    ) -> [any Internals.DecompressionAlgorithm]? {
        guard let request, request.value(forHTTPHeaderField: "Accept-Encoding") == nil else {
            return decompression
        }

        return nil
    }

    /// The `Content-Encoding`s a download continued from resume data may be decoded from, as the
    /// task description keeps them. `nil` when nothing is decoded.
    ///
    /// What the request that stopped sent still decides, as in `decompression(_:resumedFrom:)`, in
    /// both directions. A request that sent no `Accept-Encoding` was decoded by the system, so
    /// nothing is. A request that sent one did take over decoding, so the file is still encoded
    /// whatever `decompression` says: when `content` was written again without the algorithms,
    /// the encodings come from the header itself and the decompressors the app registered stand
    /// in for them. Without that, the still-encoded file would have been handed to `destination`
    /// as `.completed`; this way a missing decompressor fails the download, as it does for any
    /// other.
    ///
    /// A header that names one of the encodings the system decodes on its own (`gzip`, `deflate`,
    /// `br`) is the app's own, and decides nothing here: a request that took over `Accept-Encoding`
    /// never lists them (a list that does is refused when the download is scheduled, see
    /// `takingOverAcceptEncoding(of:for:)`), so they only show up when the app set the header, or
    /// the system added it. Such a download is decoded by the system and what it did not decode is
    /// delivered as it came, the same answer a new download with that header gets. Without this, a
    /// header like `gzip, deflate, br, zstd` written by the app, that was delivered raw the first
    /// time, would download all of the file again and fail with
    /// ``BackgroundDownloadMissingDecompressorError`` for `zstd`, with no resume data. What is
    /// left after the others are removed cannot be told from a takeover by the header alone, so a
    /// header with custom names only (`zstd`) still decides, and fails without a decompressor, as
    /// a takeover does.
    static func acceptedEncodings(
        _ decompression: [any Internals.DecompressionAlgorithm]?,
        resumedFrom request: URLRequest?
    ) -> [String]? {
        if let algorithms = Self.decompression(decompression, resumedFrom: request) {
            return algorithms.map { $0.contentEncodingValue.lowercased() }
        }

        guard
            decompression == nil,
            let header = request?.value(forHTTPHeaderField: "Accept-Encoding")
        else {
            return nil
        }

        let systemDecoded: Set<String> = ["gzip", "x-gzip", "deflate", "br", "identity", "*"]

        let encodings =
            header
            .split(separator: ",")
            .compactMap { $0.split(separator: ";").first }
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        guard !encodings.contains(where: systemDecoded.contains) else {
            return nil
        }

        return encodings.isEmpty ? nil : encodings
    }

    /// Every `Content-Encoding` field of `response`, comma-split, lowercased and without
    /// `identity`, which undoes nothing.
    static func contentEncodings(of response: URLResponse?) -> [String] {
        guard let value = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Encoding") else {
            return []
        }

        return
            value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && $0 != "identity" }
    }
}

#endif
