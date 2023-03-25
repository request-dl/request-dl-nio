/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public struct Certificate {

    enum Source {
        case file(String)
        case bytes([UInt8])
    }

    let source: Source
    let format: CertificateFormat

    public init(_ file: String, format: CertificateFormat) {
        self.source = .file(file)
        self.format = format
    }

    public init(_ bytes: [UInt8], format: CertificateFormat) {
        self.source = .bytes(bytes)
        self.format = format
    }
}

extension Certificate {

    func build() throws -> NIOSSLCertificate {
        switch source {
        case .bytes(let bytes):
            return try NIOSSLCertificate(bytes: bytes, format: format.build())
        case .file(let file):
            return try NIOSSLCertificate(file: file, format: format.build())
        }
    }
}