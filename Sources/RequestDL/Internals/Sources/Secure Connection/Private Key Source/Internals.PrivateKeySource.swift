/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Internals {

    enum PrivateKeySource: Sendable, Equatable {

        case file(String)
        case privateKey(PrivateKey)
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
