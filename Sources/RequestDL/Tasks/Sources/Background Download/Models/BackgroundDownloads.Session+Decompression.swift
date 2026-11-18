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
        taskDescription: String?,
        id: String,
        destination: URL
    ) throws -> URL? {
        guard let accepted = Self.decodeAcceptedEncodings(taskDescription) else {
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

        guard let algorithm = decompressor(forEncoding: encoding, id: id) else {
            throw accepted.contains(encoding)
                ? BackgroundDownloadMissingDecompressorError(contentEncoding: encoding)
                : UnsupportedContentEncodingError(value: encoding)
        }

        let output = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).decoding")

        guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: output.path])
        }

        do {
            try Self.decode(from: location, to: output, using: algorithm)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }

        return output
    }

    /// The pure part of ``decodedFile(from:response:taskDescription:id:destination:)``, kept
    /// apart so it can be tested without a download.
    static func decode(
        from input: URL,
        to output: URL,
        using algorithm: any Internals.DecompressionAlgorithm
    ) throws {
        let reader = try FileHandle(forReadingFrom: input)
        defer { try? reader.close() }

        let writer = try FileHandle(forWritingTo: output)
        defer { try? writer.close() }

        var stream = try algorithm()
        var hasInput = false

        while let chunk = try reader.read(upToCount: decodingChunkSize), !chunk.isEmpty {
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
