/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Internals {

    enum PrivateKeySource {

        case file(String)
        case privateKey(PrivateKeyRepresentable)
    }
}

extension Internals.PrivateKeySource {

    func build() throws -> NIOSSL.NIOSSLPrivateKeySource {
        switch self {
        case .file(let path):
            return .file(path)
        case .privateKey(let privateKey):
            return try .privateKey(privateKey.build())
        }
    }
}

extension Internals.PrivateKeySource: Equatable {

    static func == (_ lhs: Self, _ rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.file(let lhs), .file(let rhs)):
            return lhs == rhs
        case (.privateKey(let lhs), .privateKey(let rhs)):
            return lhs.isEqual(to: rhs)
        default:
            return false
        }
    }
}
