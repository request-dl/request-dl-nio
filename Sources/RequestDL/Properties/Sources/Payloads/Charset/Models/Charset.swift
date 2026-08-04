//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
#endif

/// Enumeration representing various character encodings (charsets) in Swift.
public enum Charset: String, Sendable, LosslessStringConvertible {

    /// The UTF-8 character encoding.
    case utf8 = "UTF-8"

    /// The ISO-8859-1 character encoding (Latin-1).
    case isoLatin1 = "ISO-8859-1"

    /// The UTF-16 character encoding.
    ///
    /// Emitted with a byte order mark, in the platform's byte order.
    case utf16 = "UTF-16"

    /// The UTF-16 Big Endian character encoding.
    case utf16BigEndian = "UTF-16BE"

    /// The UTF-16 Little Endian character encoding.
    case utf16LittleEndian = "UTF-16LE"

    /// The UTF-32 character encoding.
    ///
    /// Emitted with a byte order mark, in the platform's byte order.
    case utf32 = "UTF-32"

    /// The UTF-32 Big Endian character encoding.
    case utf32BigEndian = "UTF-32BE"

    /// The UTF-32 Little Endian character encoding.
    case utf32LittleEndian = "UTF-32LE"

    // MARK: - Public properties

    public var description: String {
        rawValue
    }

    // MARK: - Inits

    /// - Note: Case insensitive, so `"utf-8"` resolves as well as `"UTF-8"`. Charset names are
    /// case insensitive per RFC 2978.
    public init?(_ description: String) {
        self.init(rawValue: description.uppercased())
    }

    // MARK: - Internal methods

    /// Encodes `string` in this charset.
    ///
    /// Written out by hand rather than delegating to `String.data(using:)`. That method, and
    /// the `String.Encoding` it takes, belong to the full Foundation and are not part of
    /// `FoundationEssentials`. This file only ever imported `Foundation.Data`, so the previous
    /// version did not compile off Apple either.
    ///
    /// The forms with an explicit endianness carry no byte order mark, because the name already
    /// says which one it is. The plain `utf16` and `utf32` do carry one, in the platform's byte
    /// order, which is what a reader has to have to make sense of them.
    ///
    /// - Throws: ``EncodingPayloadError`` with ``EncodingPayloadError/Context/invalidStringEncoding``
    /// when a scalar has no representation in the target charset, which only Latin-1 can hit.
    func encode(_ string: String) throws -> Data {
        switch self {
        case .utf8:
            return Data(string.utf8)

        case .isoLatin1:
            return try encodeLatin1(string)

        case .utf16:
            return encodeUTF16(string, bigEndian: !Self.isLittleEndian, byteOrderMark: true)

        case .utf16BigEndian:
            return encodeUTF16(string, bigEndian: true, byteOrderMark: false)

        case .utf16LittleEndian:
            return encodeUTF16(string, bigEndian: false, byteOrderMark: false)

        case .utf32:
            return encodeUTF32(string, bigEndian: !Self.isLittleEndian, byteOrderMark: true)

        case .utf32BigEndian:
            return encodeUTF32(string, bigEndian: true, byteOrderMark: false)

        case .utf32LittleEndian:
            return encodeUTF32(string, bigEndian: false, byteOrderMark: false)
        }
    }

    // MARK: - Private static properties

    /// `littleEndian` is the identity on a little endian machine and a byte swap on a big
    /// endian one, so this is a real test rather than a tautology.
    private static var isLittleEndian: Bool {
        UInt16(1).littleEndian == 1
    }

    // MARK: - Private methods

    /// One byte per scalar, for the 256 scalars Latin-1 can express.
    private func encodeLatin1(_ string: String) throws -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity(string.unicodeScalars.count)

        for scalar in string.unicodeScalars {
            guard let byte = UInt8(exactly: scalar.value) else {
                throw EncodingPayloadError(.invalidStringEncoding)
            }

            bytes.append(byte)
        }

        return Data(bytes)
    }

    /// Two bytes per code unit. `String.UTF16View` already splits astral scalars into surrogate
    /// pairs, so there is nothing to do about them here.
    private func encodeUTF16(_ string: String, bigEndian: Bool, byteOrderMark: Bool) -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity((string.utf16.count + (byteOrderMark ? 1 : 0)) * 2)

        if byteOrderMark {
            Self.append(0xFEFF as UInt16, to: &bytes, bigEndian: bigEndian)
        }

        for unit in string.utf16 {
            Self.append(unit, to: &bytes, bigEndian: bigEndian)
        }

        return Data(bytes)
    }

    /// Four bytes per scalar. Scalars, not code units: UTF-32 stores whole code points.
    private func encodeUTF32(_ string: String, bigEndian: Bool, byteOrderMark: Bool) -> Data {
        var bytes = [UInt8]()
        bytes.reserveCapacity((string.unicodeScalars.count + (byteOrderMark ? 1 : 0)) * 4)

        if byteOrderMark {
            Self.append(0x0000_FEFF as UInt32, to: &bytes, bigEndian: bigEndian)
        }

        for scalar in string.unicodeScalars {
            Self.append(scalar.value, to: &bytes, bigEndian: bigEndian)
        }

        return Data(bytes)
    }

    // MARK: - Private static methods

    private static func append(_ value: UInt16, to bytes: inout [UInt8], bigEndian: Bool) {
        let ordered = bigEndian ? value.bigEndian : value.littleEndian
        withUnsafeBytes(of: ordered) { bytes.append(contentsOf: $0) }
    }

    private static func append(_ value: UInt32, to bytes: inout [UInt8], bigEndian: Bool) {
        let ordered = bigEndian ? value.bigEndian : value.littleEndian
        withUnsafeBytes(of: ordered) { bytes.append(contentsOf: $0) }
    }
}
