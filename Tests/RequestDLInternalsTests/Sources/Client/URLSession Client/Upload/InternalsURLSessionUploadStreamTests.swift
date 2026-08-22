//
// See LICENSE for this package's licensing information.
//

import NIOCore
import Testing

@testable import RequestDLInternals

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Phase 5f of `URLSESSION_TASK.md` -- unit coverage for `Internals.URLSessionUploadStream`'s
/// bounded-buffer bridge, independent of `URLSession`/a real network round trip (that's
/// `RequestConfigurationURLSessionClientUploadTests` in `RequestDLTests`). This is the layer
/// the type's own doc comment calls "the part actually worth getting right."
struct InternalsURLSessionUploadStreamTests {

    @Test
    func uploadStream_whenReadInSmallSlices_deliversAllBytesInOrder() async throws {
        // Given -- a recognizable, non-repeating byte pattern, so any reordering or corruption
        // shows up as a content mismatch, not just a wrong total.
        let payload = Data((0..<10_000).map { UInt8($0 % 251) })
        let chunkSize = 777

        let (stream, continuation) = AsyncStream<ByteBuffer>.makeStream()
        for start in Swift.stride(from: 0, to: payload.count, by: chunkSize) {
            let end = Swift.min(start + chunkSize, payload.count)
            continuation.yield(ByteBuffer(bytes: payload[start..<end]))
        }
        continuation.finish()

        let uploadStream = Internals.URLSessionUploadStream(body: stream, highWaterMark: 512)
        uploadStream.open()
        defer { uploadStream.close() }

        // When -- read in a size that lines up with neither the source chunk size above nor the
        // high water mark, so at least some reads span a chunk boundary inside `Buffer`.
        var received = Data()
        var readBuffer = [UInt8](repeating: 0, count: 333)

        while true {
            let bytesRead = readBuffer.withUnsafeMutableBufferPointer { pointer in
                uploadStream.read(pointer.baseAddress!, maxLength: pointer.count)
            }

            #expect(bytesRead >= 0)
            guard bytesRead > .zero else { break }
            received.append(contentsOf: readBuffer[0..<bytesRead])
        }

        // Then
        #expect(received == payload)
        #expect(uploadStream.streamStatus == .atEnd)
    }

    @Test
    func uploadStream_whenBackpressureIsExercised_stillDeliversEverything() async throws {
        // Given -- a single chunk far larger than `highWaterMark`, forcing `Buffer.push(_:)` to
        // genuinely suspend waiting for `read` to drain room mid-chunk, not just once at the end.
        let payload = Data((0..<50_000).map { _ in UInt8.random(in: .min ... .max) })

        let (stream, continuation) = AsyncStream<ByteBuffer>.makeStream()
        continuation.yield(ByteBuffer(bytes: payload))
        continuation.finish()

        let uploadStream = Internals.URLSessionUploadStream(body: stream, highWaterMark: 64)
        uploadStream.open()
        defer { uploadStream.close() }

        // When
        var received = Data()
        var readBuffer = [UInt8](repeating: 0, count: 4_096)

        while true {
            let bytesRead = readBuffer.withUnsafeMutableBufferPointer { pointer in
                uploadStream.read(pointer.baseAddress!, maxLength: pointer.count)
            }
            guard bytesRead > .zero else { break }
            received.append(contentsOf: readBuffer[0..<bytesRead])
        }

        // Then
        #expect(received == payload)
    }

    @Test
    func uploadStream_whenClosedBeforeExhausted_readReturnsWithoutHanging() async throws {
        // Given -- far more data than `highWaterMark` and a source that never finishes, so if
        // `close()` failed to release a `read` blocked on `dataAvailable` (or a producer blocked
        // on room), this test would hang instead of failing.
        let (stream, continuation) = AsyncStream<ByteBuffer>.makeStream()
        continuation.yield(ByteBuffer(repeating: 0, count: 1_000_000))

        let uploadStream = Internals.URLSessionUploadStream(body: stream, highWaterMark: 16)
        uploadStream.open()

        // When
        uploadStream.close()

        var byte: UInt8 = 0
        let bytesRead = uploadStream.read(&byte, maxLength: 1)

        // Then
        #expect(bytesRead == .zero)

        continuation.finish()
    }
}

#endif
