//
// See LICENSE for this package's licensing information.
//

import NIOCore
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

struct InternalsByteURLTests {

    @Test
    func byteURL_whenInitEmpty() {
        // Given
        let url = Internals.ByteURL()

        // Then
        #expect(url.buffer.writerIndex == .zero)
        #expect(url.buffer.readerIndex == .zero)
        #expect(url.writtenBytes == .zero)
    }

    @Test
    func byteURL_whenInitWithBuffer() async {
        // Given
        let buffer = await ByteBuffer(data: .randomData(length: 64))

        // When
        let url = Internals.ByteURL(buffer)

        // Then
        #expect(url.buffer.writerIndex == 64)
        #expect(url.buffer.readerIndex == .zero)
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
        #expect(url.buffer.writerIndex == 64)
        #expect(url.buffer.readerIndex == .zero)
        #expect(url.writtenBytes == 64)
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
