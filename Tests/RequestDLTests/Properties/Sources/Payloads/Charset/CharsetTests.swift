/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct CharsetTests {

    @Test
    func charset_whenUTF8() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf8

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == verbatim.data(using: .utf8))
    }

    @Test
    func charset_whenISOLatin1() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.isoLatin1

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == verbatim.data(using: .isoLatin1))
    }

    @Test
    func charset_whenUTF16() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf16

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == verbatim.data(using: .utf16))
    }

    @Test
    func charset_whenUTF16BigEndian() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf16BigEndian

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == verbatim.data(using: .utf16BigEndian))
    }

    @Test
    func charset_whenUTF16LittleEndian() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf16LittleEndian

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == verbatim.data(using: .utf16LittleEndian))
    }

    @Test
    func charset_whenUTF32() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf32

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == verbatim.data(using: .utf32))
    }

    @Test
    func charset_whenUTF32BigEndian() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf32BigEndian

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == verbatim.data(using: .utf32BigEndian))
    }

    @Test
    func charset_whenUTF32LittleEndian() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf32LittleEndian

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == verbatim.data(using: .utf32LittleEndian))
    }
}
