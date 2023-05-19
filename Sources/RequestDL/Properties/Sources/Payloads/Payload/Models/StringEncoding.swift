/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public enum Charset: String, Sendable {

    case utf8 = "UTF-8"
}

extension Charset: LosslessStringConvertible {

    public var description: String {
        rawValue
    }

    public init?(_ description: String) {
        self.init(rawValue: description.uppercased())
    }
}

extension Charset {

    func encode(_ string: String) throws -> Data {
        switch self {
        case .utf8:
            return try encode(string, using: .utf8)
        }
    }

    private func encode(_ string: String, using encoding: String.Encoding) throws -> Data {
        guard let data = string.data(using: encoding) else {
            throw EncodingPayloadError()
        }

        return data
    }
}

private struct CharsetEnvironmentKey: EnvironmentKey {

    static var defaultValue: Charset = .utf8
}

extension EnvironmentValues {

    var charset: Charset {
        get { self[CharsetEnvironmentKey.self] }
        set { self[CharsetEnvironmentKey.self] = newValue }
    }
}

extension Property {

    public func charset(_ charset: Charset) -> some Property {
        environment(\.charset, charset)
    }
}
