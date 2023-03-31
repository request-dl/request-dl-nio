/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct TLSCipher: RawRepresentable, Hashable, Sendable {

    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    init(_ cipher: Internals.NIOTLSCipher) {
        self.init(rawValue: cipher.rawValue)
    }
}

extension TLSCipher {

    func build() -> Internals.NIOTLSCipher {
        .init(rawValue: rawValue)
    }
}
