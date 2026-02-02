/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public enum SPKIHashError: Error, Sendable, Hashable, CustomStringConvertible {

    case invalidBase64(String)
    case invalidLength(expected: Int, got: Int)

    public var description: String {
        switch self {
        case .invalidBase64(let value):
            return "Invalid Base64 string: '\(value.prefix(16))...'"
        case .invalidLength(let expected, let got):
            return "Invalid hash length: expected \(expected) bytes, got \(got)"
        }
    }
}
