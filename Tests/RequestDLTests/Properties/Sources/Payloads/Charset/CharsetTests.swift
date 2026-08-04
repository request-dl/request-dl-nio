//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
#endif

struct CharsetTests {

    @Test
    func charset_whenUTF8() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf8

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == Data(verbatim.utf8))
    }

    @Test
    func charset_whenISOLatin1() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.isoLatin1

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == Data(verbatim.unicodeScalars.map { UInt8($0.value) }))
    }

    @Test
    func charset_whenUTF16() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf16

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == referenceUTF16(verbatim, bigEndian: !Self.isLittleEndian, byteOrderMark: true))
    }

    @Test
    func charset_whenUTF16BigEndian() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf16BigEndian

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == referenceUTF16(verbatim, bigEndian: true, byteOrderMark: false))
    }

    @Test
    func charset_whenUTF16LittleEndian() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf16LittleEndian

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == referenceUTF16(verbatim, bigEndian: false, byteOrderMark: false))
    }

    @Test
    func charset_whenUTF32() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf32

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == referenceUTF32(verbatim, bigEndian: !Self.isLittleEndian, byteOrderMark: true))
    }

    @Test
    func charset_whenUTF32BigEndian() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf32BigEndian

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == referenceUTF32(verbatim, bigEndian: true, byteOrderMark: false))
    }

    @Test
    func charset_whenUTF32LittleEndian() throws {
        // Given
        let verbatim = "Hello world"
        let charset = Charset.utf32LittleEndian

        // When
        let sut = try charset.encode(verbatim)

        // Then
        #expect(sut == referenceUTF32(verbatim, bigEndian: false, byteOrderMark: false))
    }
}

extension CharsetTests {

    /// `littleEndian` is the identity on a little endian machine and a byte swap on a big endian
    /// one, matching `Charset`'s own check.
    fileprivate static var isLittleEndian: Bool {
        UInt16(1).littleEndian == 1
    }

    /// A from-scratch reference encoder, deliberately independent of `Charset`'s own
    /// `withUnsafeBytes(of:)`-based implementation — plain bit shifting instead — so this test
    /// can catch a mistake in either without checking one against a copy of itself.
    ///
    /// `String(data:encoding:)`/`String.Encoding` are not part of `FoundationEssentials`, so
    /// they cannot serve as the reference here the way they once did.
    fileprivate func referenceUTF16(_ string: String, bigEndian: Bool, byteOrderMark: Bool) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity((string.utf16.count + (byteOrderMark ? 1 : 0)) * 2)

        if byteOrderMark {
            bytes += splitBigEndianFirst(0xFEFF as UInt16, bigEndian: bigEndian)
        }

        for unit in string.utf16 {
            bytes += splitBigEndianFirst(unit, bigEndian: bigEndian)
        }

        return Data(bytes)
    }

    fileprivate func referenceUTF32(_ string: String, bigEndian: Bool, byteOrderMark: Bool) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity((string.unicodeScalars.count + (byteOrderMark ? 1 : 0)) * 4)

        if byteOrderMark {
            bytes += splitBigEndianFirst(0x0000_FEFF as UInt32, bigEndian: bigEndian)
        }

        for scalar in string.unicodeScalars {
            bytes += splitBigEndianFirst(scalar.value, bigEndian: bigEndian)
        }

        return Data(bytes)
    }

    fileprivate func splitBigEndianFirst(_ value: UInt16, bigEndian: Bool) -> [UInt8] {
        let high = UInt8(value >> 8)
        let low = UInt8(value & 0xFF)
        return bigEndian ? [high, low] : [low, high]
    }

    fileprivate func splitBigEndianFirst(_ value: UInt32, bigEndian: Bool) -> [UInt8] {
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        return bigEndian ? bytes : bytes.reversed()
    }
}
