/*
 See LICENSE for this package's licensing information.
*/

import Foundation

enum SPKIHashSource: Sendable, Hashable {

    case base64String(String)
    case rawData(Data)

    func base64EncodedString() throws(SPKIHashError) -> String {
        try self.normalizedValue()
    }

    private func normalizedValue() throws(SPKIHashError) -> String {
        switch self {
        case .base64String(let string):
            return try Self.normalize(base64String: string)
        case .rawData(let data):
            return try Self.normalize(data: data)
        }
    }

    private static func normalize(base64String: String) throws(SPKIHashError) -> String {
        let cleaned = base64String.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = Data(base64Encoded: cleaned) else {
            throw SPKIHashError.invalidBase64(base64String)
        }

        guard data.count == 32 else {
            throw SPKIHashError.invalidLength(expected: 32, got: data.count)
        }

        return data.base64EncodedString()
    }

    private static func normalize(data: Data) throws(SPKIHashError) -> String {
        guard data.count == 32 else {
            throw SPKIHashError.invalidLength(expected: 32, got: data.count)
        }
        return data.base64EncodedString()
    }
}
