/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public protocol CertificatePrivateKeyRepresentable {

    func build() throws -> NIOSSLPrivateKey
}
