/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public protocol StringEncoding: Sendable, Hashable, CustomStringConvertible {

    func encode(_ string: String) throws -> Data
}


public struct UTF8StringEncoding: StringEncoding {

    public var description = "UTF-8"

    public func encode(_ string: String) throws -> Data {
        Data(string.utf8)
    }
}

extension StringEncoding where Self == UTF8StringEncoding {

    public static var utf8: UTF8StringEncoding {
        UTF8StringEncoding()
    }
}

@available(*, deprecated)
struct _StringEncoding: StringEncoding {

    let description: String
    let encoding: String.Encoding

    init(_ encoding: String.Encoding) {
        self.description = Self.charset(for: encoding) ?? ""
        self.encoding = encoding
    }

    private static func charset(for encoding: String.Encoding) -> String? {
        switch encoding {
        case .ascii:
            return "US-ASCII"
        case .nextstep:
            return "NEXTSTEP"
        case .japaneseEUC:
            return "EUC-JP"
        case .utf8:
            return "UTF-8"
        case .isoLatin1:
            return "ISO-8859-1"
        case .symbol:
            return "MACSYMBOL"
        case .nonLossyASCII:
            return "ASCII"
        case .shiftJIS:
            return "Shift_JIS"
        case .isoLatin2:
            return "ISO-8859-2"
        case .unicode:
            return "UTF-16"
        case .windowsCP1251:
            return "Windows-1251"
        case .windowsCP1252:
            return "Windows-1252"
        case .windowsCP1253:
            return "Windows-1253"
        case .windowsCP1254:
            return "Windows-1254"
        case .windowsCP1250:
            return "Windows-1250"
        case .iso2022JP:
            return "ISO-2022-JP"
        case .macOSRoman:
            return "macintosh"
        case .utf16:
            return "UTF-16"
        case .utf16BigEndian:
            return "UTF-16BE"
        case .utf16LittleEndian:
            return "UTF-16LE"
        case .utf32:
            return "UTF-32"
        case .utf32BigEndian:
            return "UTF-32BE"
        case .utf32LittleEndian:
            return "UTF-32LE"
        default:
            return nil
        }
    }

    func encode(_ string: String) throws -> Data {
        guard
            !description.isEmpty,
            let data = string.data(using: encoding)
        else { throw EncodingPayloadError() }

        return data
    }
}
