/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Internals {

    struct Certificate: Hashable {

        enum Source: Hashable {
            case file(String)
            case bytes([UInt8])
        }

        let source: Source
        let format: Format

        init(_ file: String, format: Format) {
            self.source = .file(file)
            self.format = format
        }

        init(_ bytes: [UInt8], format: Format) {
            self.source = .bytes(bytes)
            self.format = format
        }
    }
}

extension Internals.Certificate {

    func build() throws -> NIOSSLCertificate {
        switch source {
        case .bytes(let bytes):
            return try NIOSSLCertificate(bytes: bytes, format: format.build())
        case .file(let file):
            return try NIOSSLCertificate(file: file, format: format.build())
        }
    }
}
