//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// `Int` is 32 bits on watchOS `arm64_32`, and a trap there is not something a 64-bit run can
/// reproduce. The boundary arithmetic is therefore a function generic over the index type, tested
/// here with `Int32` standing in for that `Int`, and the read paths are tested with a length that
/// does not fit any `Int` (`UInt64.max`), which takes the same branch a 3 GiB length takes there.
/// Only the in-memory stream can be given such a length: the file stream hands it to
/// `NIOFileSystem`, which reserves it as a buffer capacity and traps on 64 bit past 4 GiB, so its
/// clamp is read, not run.
struct InternalsBufferBoundsTests {

    // MARK: - Write end

    @Test
    func end_whenTheWriteFits_returnsTheOffsetRightAfterIt() {
        #expect(Internals.BufferBounds.end(ofWritingAt: 10, count: 5, as: Int.self) == 15)
        #expect(Internals.BufferBounds.end(ofWritingAt: .zero, count: .zero, as: Int.self) == .zero)
    }

    @Test
    func end_atTheLastRepresentableIndex_acceptsAnEmptyWriteAndRefusesOneByte() {
        let last = UInt64(Int.max)

        #expect(Internals.BufferBounds.end(ofWritingAt: last, count: .zero, as: Int.self) == Int.max)
        #expect(Internals.BufferBounds.end(ofWritingAt: last, count: 1, as: Int.self) == nil)
        #expect(Internals.BufferBounds.end(ofWritingAt: last - 4, count: 4, as: Int.self) == Int.max)
        #expect(Internals.BufferBounds.end(ofWritingAt: last - 4, count: 5, as: Int.self) == nil)
    }

    @Test
    func end_asInt32_refusesTheWriteThatCrossesTwoGibInsteadOfWrapping() {
        // A 32 bit `Int` stops at 2 GiB - 1. The same offsets are fine on a 64 bit `Int`.
        let twoGiB = UInt64(Int32.max)

        #expect(Internals.BufferBounds.end(ofWritingAt: twoGiB - 1, count: 1, as: Int32.self) == Int32.max)
        #expect(Internals.BufferBounds.end(ofWritingAt: twoGiB, count: 1, as: Int32.self) == nil)
        #expect(Internals.BufferBounds.end(ofWritingAt: twoGiB + 1, count: .zero, as: Int32.self) == nil)
        #expect(Internals.BufferBounds.end(ofWritingAt: .zero, count: Int(Int32.max) + 1, as: Int32.self) == nil)

        #expect(Internals.BufferBounds.end(ofWritingAt: twoGiB, count: 1, as: Int.self) == Int(Int32.max) + 1)
    }

    @Test
    func end_whenTheIndexDoesNotFitAtAll_refusesIt() {
        #expect(Internals.BufferBounds.end(ofWritingAt: .max, count: .zero, as: Int.self) == nil)
        #expect(Internals.BufferBounds.end(ofWritingAt: UInt64(Int.max) + 1, count: 1, as: Int.self) == nil)
    }

    @Test
    func end_whenTheCountIsNegative_refusesIt() {
        #expect(Internals.BufferBounds.end(ofWritingAt: 10, count: -1, as: Int.self) == nil)
    }

    // MARK: - Writes that would end past `Int.max`

    @Test
    func buffer_writeData_whenItWouldEndPastTheLastIndex_isRefusedAndLeavesTheWriterWhereItWas() async {
        var buffer = Internals.Buffer(Internals.ByteURL())
        buffer.moveWriterIndex(to: Int.max - 2)

        await buffer.writeData(Data("Hello".utf8))

        #expect(buffer.writerIndex == Int.max - 2)
    }

    @Test
    func buffer_setData_whenItWouldEndPastTheLastIndex_isRefused() async throws {
        let url = Internals.ByteURL()
        let buffer = Internals.Buffer(url)

        try await buffer.setData(Data("Hello".utf8), at: Int.max - 2)

        #expect(url.writtenBytes == .zero)
    }

    // MARK: - Reads with a length no `Int` holds

    // Exit tests spawn a child process, which only macOS and Linux support here. They are used
    // because the code these replace trapped, and a trap would take the whole test runner down.
    #if os(macOS) || os(Linux)
    @Test
    func byteStream_readData_withALengthNoIntHolds_readsWhatIsThere() async {
        await #expect(processExitsWith: .success) {
            let url = Internals.ByteURL(adopting: Data("Hello world".utf8))
            let stream = try await Internals.ByteStreamBuffer(readingFrom: .init(url))

            let data = try await stream.readData(length: .max)

            guard data == Data("Hello world".utf8) else {
                fatalError("The read returned \(String(describing: data))")
            }
        }
    }
    #endif

    // MARK: - 64 bit behavior is unchanged

    @Test
    func byteStream_readData_withALengthPastTheEnd_stillReadsOnlyWhatIsThere() async throws {
        let url = Internals.ByteURL(adopting: Data("Hello world".utf8))
        let stream = try await Internals.ByteStreamBuffer(readingFrom: .init(url))

        let data = try await stream.readData(length: UInt64(Int.max))
        let offset = try await stream.offset

        #expect(data == Data("Hello world".utf8))
        #expect(offset == 11)
    }

    @Test
    func fileStream_readData_withALengthPastTheEnd_stillReadsOnlyWhatIsThere() async throws {
        try await withTemporaryFileURL("stream.bin") { url in
            let writer = try await Internals.FileStreamBuffer(writingTo: .init(url))
            try await writer.writeData(Data("Hello world".utf8))
            try await writer.close()

            let reader = try await Internals.FileStreamBuffer(readingFrom: .init(url))
            let data = try await reader.readData(length: 1_024)
            let offset = try await reader.offset
            try await reader.close()

            #expect(data == Data("Hello world".utf8))
            #expect(offset == 11)
        }
    }
}
