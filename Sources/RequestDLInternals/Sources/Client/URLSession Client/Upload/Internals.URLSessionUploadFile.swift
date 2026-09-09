//
// See LICENSE for this package's licensing information.
//

// Workaround for a confirmed CFNetwork bug (root-caused, but not fixed upstream or yet reported):
// `uploadTask(withStreamedRequest:)` never recognizes end-of-body for a custom `InputStream` --
// confirmed across four servers and three independently-written subclasses, plus a genuine
// `CFReadStream` built from raw callbacks, that every callback plausibly involved
// (`copyProperty`/`setProperty`/`getBuffer`/object-identity) was ruled out as the cause -- only
// Foundation's own concrete, singular `InputStream(data:)` class ever completes. The earlier
// `Internals.URLSessionUploadStream` (an `InputStream` subclass) hit exactly that bug and is gone;
// this replaces it with two different `URLSession` code paths -- `uploadTask(with:from:)` for a
// body small enough to just hold in memory, `uploadTask(with:fromFile:)` for everything else --
// neither of which touches `InputStream`/`needNewBodyStream` at all, so neither is affected.

#if canImport(Darwin)

import NIOCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

extension Internals {

    /// Materializes an upload body (`Internals.BodySequence`, or `RequestBody` itself from the
    /// `RequestDL` module -- both conform to `AsyncSequence<ByteBuffer>`) into whichever of
    /// `URLSession`'s two non-`InputStream` upload shapes fits, so `Internals.URLSessionClient`
    /// never has to stream through a custom `InputStream`. See this file's header comment for why
    /// that matters.
    ///
    /// Most request bodies (a JSON payload, a small form, ordinary `Payload(data:)` uploads) are
    /// already comfortably small -- writing every one of those to a temporary file before every
    /// request would be needless disk I/O for something that already fits in memory. Only a body
    /// that turns out to be genuinely large spills to disk, and only past the point where it
    /// stopped being cheap to just hold onto.
    enum URLSessionUploadFile {

        /// Below this many bytes, `write(body:)` keeps the whole body in memory (`.data`) rather
        /// than spilling to a temporary file. Deliberately generous -- most everyday bodies
        /// (JSON, form fields, small-to-medium payloads) land well under it, and 8 MiB held
        /// briefly in memory for one in-flight upload is not a meaningful cost on any platform
        /// this executor targets.
        static let inMemoryThreshold = 8 * 1_024 * 1_024

        /// Where an upload body ended up, whether by draining it (`write(body:)`) or by the
        /// caller already knowing it's sitting on disk untouched (`RequestBody.wholeFileURL`).
        enum Materialized {
            /// The whole body, still in memory -- upload via `uploadTask(with:from:)`.
            case data(Data)
            /// The body spilled past `inMemoryThreshold` while draining it, now sitting in a
            /// temporary file this package created -- upload via `uploadTask(with:fromFile:)`.
            /// The caller owns the file from here -- remove it
            /// (`Internals.FileBufferURL.removeIfTemporary()`) once the upload task, success or
            /// failure, is done with it.
            case file(Internals.FileBufferURL)
            /// The body was never drained at all -- it was already sitting in a file somebody
            /// else owns (`RequestBody.wholeFileURL`'s `Payload(url:)` case). Upload via
            /// `uploadTask(with:fromFile:)`, same as `.file`, but this URL is never removed
            /// afterward -- it isn't this package's file to delete.
            case existingFile(URL)
        }

        /// Drains `body` up to `inMemoryThreshold` bytes without touching disk. If that's the
        /// whole body, returns `.data` with nothing written anywhere. Otherwise, everything
        /// buffered so far plus the remainder of `body` is written to a fresh temporary file, and
        /// `.file` is returned instead.
        static func write<Body: AsyncSequence & Sendable>(
            body: Body,
            inMemoryThreshold: Int = Self.inMemoryThreshold
        ) async throws -> Materialized where Body.Element == ByteBuffer {
            var iterator = body.makeAsyncIterator()
            var buffered = Data()
            var reachedEnd = false

            while buffered.count <= inMemoryThreshold {
                guard let chunk = try await iterator.next() else {
                    reachedEnd = true
                    break
                }
                buffered.append(contentsOf: chunk.readableBytesView)
            }

            guard !reachedEnd else {
                return .data(buffered)
            }

            let bufferURL = Internals.FileBufferURL.temporaryURL
            let stream = try await Internals.FileStreamBuffer(writingTo: bufferURL)

            do {
                try await stream.writeData(buffered)

                while let chunk = try await iterator.next() {
                    try await stream.writeData(Data(chunk.readableBytesView))
                }

                try await stream.close()
            } catch {
                try? await stream.close()
                await bufferURL.removeIfTemporary()
                throw error
            }

            return .file(bufferURL)
        }
    }
}

#endif
