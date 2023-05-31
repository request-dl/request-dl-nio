/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// Enumeration representing various character encodings (charsets) in Swift.
public enum Charset: String, Sendable, LosslessStringConvertible {

    /// The UTF-8 character encoding.
    case utf8 = "UTF-8"

    /// The ISO-8859-1 character encoding (Latin-1).
    case isoLatin1 = "ISO-8859-1"

    /// The UTF-16 character encoding.
    case utf16 = "UTF-16"

    /// The UTF-16 Big Endian character encoding.
    case utf16BigEndian = "UTF-16BE"

    /// The UTF-16 Little Endian character encoding.
    case utf16LittleEndian = "UTF-16LE"

    /// The UTF-32 character encoding.
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

    public init?(_ description: String) {
        self.init(rawValue: description.uppercased())
    }

    // MARK: - Internal methods

    func encode(_ string: String) throws -> Data {
        switch self {
        case .utf8:
            return try encode(string, using: .utf8)
        case .isoLatin1:
            return try encode(string, using: .isoLatin1)
        case .utf16:
            return try encode(string, using: .utf16)
        case .utf16BigEndian:
            return try encode(string, using: .utf16BigEndian)
        case .utf16LittleEndian:
            return try encode(string, using: .utf16LittleEndian)
        case .utf32:
            return try encode(string, using: .utf32)
        case .utf32BigEndian:
            return try encode(string, using: .utf32BigEndian)
        case .utf32LittleEndian:
            return try encode(string, using: .utf32LittleEndian)
        }
    }

    // MARK: - Private methods

    private func encode(_ string: String, using encoding: String.Encoding) throws -> Data {
        guard let data = string.data(using: encoding) else {
            throw EncodingPayloadError(.invalidStringEncoding)
        }

        return data
    }
}
