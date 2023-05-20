/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

// swiftlint:disable file_length type_body_length
class CharsetTests: XCTestCase {

    func testCharset_whenUTF8() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf8

        // When
        let sut = try charset.encode(verbatim)

        // Then
        XCTAssertEqual(sut, verbatim.data(using: .utf8))
    }

    func testCharset_whenISOLatin1() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.isoLatin1

        // When
        let sut = try charset.encode(verbatim)

        // Then
        XCTAssertEqual(sut, verbatim.data(using: .isoLatin1))
    }

    func testCharset_whenUTF16() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf16

        // When
        let sut = try charset.encode(verbatim)

        // Then
        XCTAssertEqual(sut, verbatim.data(using: .utf16))
    }

    func testCharset_whenUTF16BigEndian() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf16BigEndian

        // When
        let sut = try charset.encode(verbatim)

        // Then
        XCTAssertEqual(sut, verbatim.data(using: .utf16BigEndian))
    }

    func testCharset_whenUTF16LittleEndian() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf16LittleEndian

        // When
        let sut = try charset.encode(verbatim)

        // Then
        XCTAssertEqual(sut, verbatim.data(using: .utf16LittleEndian))
    }

    func testCharset_whenUTF32() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf32

        // When
        let sut = try charset.encode(verbatim)

        // Then
        XCTAssertEqual(sut, verbatim.data(using: .utf32))
    }

    func testCharset_whenUTF32BigEndian() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf32BigEndian

        // When
        let sut = try charset.encode(verbatim)

        // Then
        XCTAssertEqual(sut, verbatim.data(using: .utf32BigEndian))
    }

    func testCharset_whenUTF32LittleEndian() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf32LittleEndian

        // When
        let sut = try charset.encode(verbatim)

        // Then
        XCTAssertEqual(sut, verbatim.data(using: .utf32LittleEndian))
    }
}
