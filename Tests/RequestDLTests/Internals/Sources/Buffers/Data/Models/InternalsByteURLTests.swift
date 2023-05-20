/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOCore
@testable import RequestDL

class InternalsByteURLTests: XCTestCase {

    func testByteURL_whenInitEmpty() {
        // Given
        let url = Internals.ByteURL()

        // Then
        XCTAssertEqual(url.buffer.writerIndex, .zero)
        XCTAssertEqual(url.buffer.readerIndex, .zero)
        XCTAssertEqual(url.writtenBytes, .zero)
    }

    func testByteURL_whenInitWithBuffer() {
        // Given
        let buffer = ByteBuffer(data: .randomData(length: 64))

        // When
        let url = Internals.ByteURL(buffer)

        // Then
        XCTAssertEqual(url.buffer.writerIndex, 64)
        XCTAssertEqual(url.buffer.readerIndex, .zero)
        XCTAssertEqual(url.writtenBytes, 64)
    }

    func testByteURL_whenInitWithBufferSlice() {
        // Given
        var buffer = ByteBuffer(data: .randomData(length: 128))

        buffer.moveReaderIndex(to: 64)

        // When
        let url = Internals.ByteURL(buffer)

        // Then
        XCTAssertEqual(url.buffer.writerIndex, 64)
        XCTAssertEqual(url.buffer.readerIndex, .zero)
        XCTAssertEqual(url.writtenBytes, 64)
    }

    func testByteURL_whenEquals() {
        // Given
        let url = Internals.ByteURL()

        // Then
        XCTAssertEqual(url, url)
    }

    func testByteURL_whenNotEquals() {
        // Given
        let url1 = Internals.ByteURL()
        let url2 = Internals.ByteURL()

        // Then
        XCTAssertNotEqual(url1, url2)
    }

    func testByteURL_whenHashable() {
        // Given
        let url1 = Internals.ByteURL()
        let url2 = Internals.ByteURL()

        // When
        var sut = Set<Internals.ByteURL>()
        sut.insert(url1)
        sut.insert(url2)
        sut.insert(url1)

        // Then
        XCTAssertEqual(sut.count, 2)
        XCTAssertEqual(sut, [url1, url2])
    }
}
