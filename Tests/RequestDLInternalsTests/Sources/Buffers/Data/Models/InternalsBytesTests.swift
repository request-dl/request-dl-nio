//
// See LICENSE for this package's licensing information.
//

import NIOCore
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

@testable import RequestDLInternals
@testable import RequestDLTestSupport

struct InternalsBytesTests {

    // MARK: - Data-backed

    @Test
    func bytes_whenInitEmpty() {
        // Given
        let bytes = Internals.Bytes()

        // Then
        #expect(bytes.readerIndex == .zero)
        #expect(bytes.writerIndex == .zero)
        #expect(bytes.readableBytes == .zero)
    }

    @Test
    func bytes_whenInitRepeating() {
        // Given
        var bytes = Internals.Bytes(repeating: .zero, count: 8)

        // Then
        #expect(bytes.readerIndex == .zero)
        #expect(bytes.writerIndex == 8)
        #expect(bytes.readableBytes == 8)
        #expect(bytes.asData() == Data(repeating: .zero, count: 8))
    }

    @Test
    func bytes_whenWritingBytes() {
        // Given
        var bytes = Internals.Bytes()

        // When
        let written = bytes.writeBytes(Data("hello".utf8))

        // Then
        #expect(written == 5)
        #expect(bytes.writerIndex == 5)
        #expect(bytes.readableBytes == 5)
        #expect(bytes.asData() == Data("hello".utf8))
    }

    @Test
    func bytes_whenWritingRepeatingByte() {
        // Given
        var bytes = Internals.Bytes()

        // When
        let written = bytes.writeRepeatingByte(1, count: 4)

        // Then
        #expect(written == 4)
        #expect(bytes.asData() == Data([1, 1, 1, 1]))
    }

    @Test
    func bytes_whenWritingInTheMiddle_preservesTheTail() {
        // Given
        var bytes = Internals.Bytes()
        bytes.writeBytes(Data("hello world".utf8))

        // When
        bytes.moveWriterIndex(to: .zero)
        bytes.writeBytes(Data("HELLO".utf8))
        bytes.moveWriterIndex(to: 11)

        // Then
        #expect(bytes.asData() == Data("HELLO world".utf8))
    }

    @Test
    func bytes_whenMovingWriterIndexPastTheEnd_fillsTheGapWithZeros() {
        // Given
        var bytes = Internals.Bytes()
        bytes.writeBytes(Data("ab".utf8))

        // When
        bytes.moveWriterIndex(to: 5)

        // Then
        #expect(bytes.readableBytes == 5)
        #expect(bytes.asData() == Data([UInt8]("ab".utf8) + [0, 0, 0]))
    }

    @Test
    func bytes_whenReadingSlice() {
        // Given
        var bytes = Internals.Bytes()
        bytes.writeBytes(Data("hello world".utf8))

        // When
        var slice = bytes.readSlice(length: 5)

        // Then
        #expect(slice?.asData() == Data("hello".utf8))
        #expect(bytes.readerIndex == 5)
        #expect(bytes.readableBytes == 6)
    }

    @Test
    func bytes_whenReadingSliceLargerThanReadable_returnsNil() {
        // Given
        var bytes = Internals.Bytes()
        bytes.writeBytes(Data("hi".utf8))

        // Then
        #expect(bytes.readSlice(length: 3) == nil)
    }

    @Test
    func bytes_whenSlicing_doesNotMoveTheOriginalCursor() {
        // Given
        var bytes = Internals.Bytes()
        bytes.writeBytes(Data("hello".utf8))
        bytes.moveReaderIndex(to: 1)

        // When
        var slice = bytes.slice()

        // Then
        #expect(slice.asData() == Data("ello".utf8))
        #expect(bytes.readerIndex == 1)
        #expect(bytes.writerIndex == 5)
    }

    @Test
    func bytes_whenClearing_dropsEveryByte() {
        // Given
        var bytes = Internals.Bytes()
        bytes.writeBytes(Data("hello".utf8))

        // When
        bytes.clear()

        // Then
        #expect(bytes.readerIndex == .zero)
        #expect(bytes.writerIndex == .zero)
        #expect(bytes.readableBytes == .zero)
    }

    // MARK: - ByteBuffer-backed

    @Test
    func bytes_whenInitFromByteBuffer() {
        // Given
        let buffer = ByteBuffer(string: "hello")

        // When
        var bytes = Internals.Bytes(buffer)

        // Then
        #expect(bytes.readerIndex == buffer.readerIndex)
        #expect(bytes.writerIndex == buffer.writerIndex)
        #expect(bytes.asData() == Data("hello".utf8))
    }

    @Test
    func bytes_whenByteBufferBacked_roundTripsThroughAsByteBuffer() {
        // Given
        let buffer = ByteBuffer(string: "hello")

        // When
        var bytes = Internals.Bytes(buffer)
        let roundTripped = bytes.asByteBuffer()

        // Then
        #expect(roundTripped == buffer)
    }

    @Test
    func bytes_whenDataBacked_materializesAsByteBuffer() {
        // Given
        var bytes = Internals.Bytes()
        bytes.writeBytes(Data("hello".utf8))

        // When
        let buffer = bytes.asByteBuffer()

        // Then
        #expect(buffer == ByteBuffer(string: "hello"))
    }

    @Test
    func bytes_whenByteBufferBacked_writeRepeatingByteGrowsPastWriterIndexSafely() {
        // `moveWriterIndex(to:)` defers straight to `NIOCore.ByteBuffer` and inherits its
        // capacity precondition — growing past it that way traps, same as real `ByteBuffer`.
        // `writeRepeatingByte(_:count:)` is the safe, backing-independent way to grow, exactly
        // as `Internals.ByteHandle.write(contentsOf:)` already relies on.

        // Given
        var buffer = ByteBuffer()
        buffer.writeString("ab")
        var bytes = Internals.Bytes(buffer)

        // When
        bytes.writeRepeatingByte(.zero, count: 3)

        // Then
        #expect(bytes.readableBytes == 5)
        #expect(bytes.asData() == Data([UInt8]("ab".utf8) + [0, 0, 0]))
    }
}
