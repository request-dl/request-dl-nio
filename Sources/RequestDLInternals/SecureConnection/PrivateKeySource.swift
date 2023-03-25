/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public enum PrivateKeySource {

    case file(String)
    case privateKey(PrivateKeyRepresentable)
}

extension PrivateKeySource {

    func build() throws -> NIOSSL.NIOSSLPrivateKeySource {
        switch self {
        case .file(let path):
            return .file(path)
        case .privateKey(let privateKey):
            return try .privateKey(privateKey.build())
        }
    }
}
