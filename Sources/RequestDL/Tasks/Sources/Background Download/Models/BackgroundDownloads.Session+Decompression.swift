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
    /// Takes over `Accept-Encoding` is what makes this necessary: it switches CFNetwork's own
    /// decoding off, for every encoding, so the file at `location` is still encoded. The decoded
    /// bytes are written next to `destination`, so that moving them there is a rename and not a
    /// copy across volumes, in `decodingChunkSize` pieces: the file is never held whole, which is
    /// the reason to stream a download to disk in the first place.
    ///
    /// - Returns: The decoded file, which the caller moves to `destination` and removes if that
    ///   fails; `nil` when `location` is already what has to be moved: the request did not take
    ///   over `Accept-Encoding` (the common case, and every download an older version scheduled),
    ///   or the response carries no encoding to undo.
    /// - Throws: ``UnsupportedContentEncodingError`` when the encoding is none of those the
    ///   request asked for, or several are stacked; ``BackgroundDownloadMissingDecompressorError``
    ///   when it is one that was asked for but no decompressor for it exists in this process; or
    ///   whatever the decompressor throws, a truncated or corrupt body included.
    func decodedFile(
        from location: URL,
        response: URLResponse?,
        task: URLSessionTask,
        destination: URL
    ) throws -> URL? {
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

        guard let algorithm = decompressor(forEncoding: encoding, task: task) else {
            throw BackgroundDownloadMissingDecompressorError(contentEncoding: encoding)
        }

        // The system's own place for what is about to replace a file: on the same volume as
        // `destination`, so that moving it there is a rename and not a copy, and one the system
        // sweeps if the app is killed mid-decode, which a file left beside `destination` would
        // never be.
        let directory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destination,
            create: true
        )
        let output = directory.appendingPathComponent(destination.lastPathComponent)

        guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
            try? FileManager.default.removeItem(at: directory)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: output.path])
        }

        do {
            try Self.decode(from: location, to: output, using: algorithm)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        return output
    }

    /// The pure part of ``decodedFile(from:response:task:destination:)``, kept apart so it can be
    /// tested without a download. `chunkSize` is a parameter only for the tests, to put the
    /// boundary between two reads where a decoder's own unit of input is cut in half.
    static func decode(
        from input: URL,
        to output: URL,
        using algorithm: any Internals.DecompressionAlgorithm,
        chunkSize: Int = decodingChunkSize
    ) throws {
        let reader = try FileHandle(forReadingFrom: input)
        defer { try? reader.close() }

        let writer = try FileHandle(forWritingTo: output)
        defer { try? writer.close() }

        var stream = try algorithm()
        var hasInput = false

        while let chunk = try reader.read(upToCount: chunkSize), !chunk.isEmpty {
            hasInput = true

            let decoded = try stream(decompressing: chunk)
            if !decoded.isEmpty {
                try writer.write(contentsOf: decoded)
            }
        }

        // A body without a byte is no stream to finish: a decoder asked for the end of something it
        // never began reports it as truncated. Same as the foreground decoding.
        if hasInput {
            let tail = try stream.finish()
            if !tail.isEmpty {
                try writer.write(contentsOf: tail)
            }
        }

        try writer.synchronize()
    }

    /// What a request that takes over `Accept-Encoding` is for: the algorithms to decode with,
    /// set on `request` as the `Accept-Encoding` it sends, or `nil` and `request` untouched when
    /// the system does the decoding. The same rule the foreground `.urlSession` executor follows:
    /// CFNetwork decodes gzip, deflate and brotli on its own, and the only way to hand it anything
    /// else is to take over `Accept-Encoding`, which switches that off for all of them.
    ///
    /// Not for `.disabled`, which keeps what a background download has always done: the system
    /// decides.
    static func takingOverAcceptEncoding(
        of request: inout URLRequest,
        for decompression: Internals.Decompression
    ) -> [any Internals.DecompressionAlgorithm]? {
        guard case .enabled(let algorithms, _) = decompression, decompression.requiresManualURLSessionHandling else {
            return nil
        }

        request.setValue(decompression.acceptEncoding, forHTTPHeaderField: "Accept-Encoding")
        return algorithms
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

    /// Every `Content-Encoding` field of `response`, comma-split, lowercased and without
    /// `identity`, which undoes nothing.
    static func contentEncodings(of response: URLResponse?) -> [String] {
        guard let value = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Encoding") else {
            return []
        }

        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && $0 != "identity" }
    }
}

#endif
