/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

protocol PrivateKeyRepresentable {

    func build() throws -> NIOSSLPrivateKey

    func isEqual(to representable: PrivateKeyRepresentable) -> Bool
}
