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

// Only `byteURL_whenInitWithBuffer`/`byteURL_whenInitWithBufferSlice` need `NIOCore.ByteBuffer`;
// `Internals.ByteURL.init(_:)` taking one only exists under `canImport(NIOCore)`.
#if canImport(NIOCore)
import NIOCore
#endif

struct InternalsByteURLTests {

    @Test
    func byteURL_whenInitEmpty() {
        // Given
        let url = Internals.ByteURL()

        // Then
        #expect(url.bytes.writerIndex == .zero)
        #expect(url.bytes.readerIndex == .zero)
        #expect(url.writtenBytes == .zero)
    }

    #if canImport(NIOCore)
    @Test
    func byteURL_whenInitWithBuffer() async {
        // Given
        let buffer = await ByteBuffer(data: .randomData(length: 64))

        // When
        let url = Internals.ByteURL(buffer)

        // Then
        #expect(url.bytes.writerIndex == 64)
        #expect(url.bytes.readerIndex == .zero)
        #expect(url.writtenBytes == 64)
    }

    @Test
    func byteURL_whenInitWithBufferSlice() async {
        // Given
        var buffer = await ByteBuffer(data: .randomData(length: 128))

        buffer.moveReaderIndex(to: 64)

        // When
        let url = Internals.ByteURL(buffer)

        // Then
        #expect(url.bytes.writerIndex == 64)
        #expect(url.bytes.readerIndex == .zero)
        #expect(url.writtenBytes == 64)
    }
    #endif

    @Test
    func byteURL_whenAdoptingData() {
        // Given
        let data = Data([1, 2, 3, 4])

        // When
        let url = Internals.ByteURL(adopting: data)

        // Then
        #expect(url.bytes.readerIndex == .zero)
        #expect(url.bytes.writerIndex == 4)
        #expect(url.writtenBytes == 4)
    }

    @Test
    func byteURL_whenAdoptingDataSlice_shouldRebaseToZero() {
        // Given
        let data = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        let slice = data[4..<8]
        #expect(slice.startIndex == 4)

        // When
        let url = Internals.ByteURL(adopting: slice)

        // Then
        #expect(url.bytes.readerIndex == .zero)
        #expect(url.bytes.writerIndex == 4)
        #expect(url.writtenBytes == 4)
    }

    @Test
    func byteURL_whenAdoptingDataSlice_shouldBeReadableThroughAHandle() throws {
        // Given
        let data = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])
        let url = Internals.ByteURL(adopting: data[4..<8])
        let handle = Internals.ByteHandle(forReadingFrom: url)

        // When
        let first = try handle.read(upToCount: 3)
        let second = try handle.read(upToCount: 3)
        let third = try handle.read(upToCount: 3)

        // Then
        #expect(first == Data([4, 5, 6]))
        #expect(second == Data([7]))
        #expect(third == nil)
    }

    @Test
    func byteURL_whenAdoptingDataThatStartsAtZero_shouldNotCopy() {
        // Given
        let data = Data(repeating: 7, count: 4_096)
        let original = data.withUnsafeBytes { $0.baseAddress }

        // When
        let url = Internals.ByteURL(adopting: data)

        // Then
        var bytes = url.bytes
        let adopted = bytes.asData().withUnsafeBytes { $0.baseAddress }
        #expect(original == adopted)
    }

    @Test
    func byteURL_whenEquals() {
        // Given
        let url = Internals.ByteURL()

        // Then
        #expect(url == url)
    }

    @Test
    func byteURL_whenNotEquals() {
        // Given
        let url1 = Internals.ByteURL()
        let url2 = Internals.ByteURL()

        // Then
        #expect(url1 != url2)
    }

    @Test
    func byteURL_whenHashable() {
        // Given
        let url1 = Internals.ByteURL()
        let url2 = Internals.ByteURL()

        // When
        var sut = Set<Internals.ByteURL>()
        sut.insert(url1)
        sut.insert(url2)
        sut.insert(url1)

        // Then
        #expect(sut.count == 2)
        #expect(sut == [url1, url2])
    }
}
