/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

extension Internals {

    struct PrivateKey: Sendable, Equatable {

        enum Source: Equatable {
            case file(String)
            case bytes([UInt8])
        }

        let source: Source
        let format: Internals.Certificate.Format
        let password: NIOSSLSecureBytes?

        init(_ file: String, format: Internals.Certificate.Format) {
            self.source = .file(file)
            self.format = format
            self.password = nil
        }

        init(_ bytes: [UInt8], format: Internals.Certificate.Format) {
            self.source = .bytes(bytes)
            self.format = format
            self.password = nil
        }

        init(_ file: String, format: Internals.Certificate.Format, password: NIOSSLSecureBytes) {
            self.source = .file(file)
            self.format = format
            self.password = password
        }

        init(_ bytes: [UInt8], format: Internals.Certificate.Format, password: NIOSSLSecureBytes) {
            self.source = .bytes(bytes)
            self.format = format
            self.password = password
        }
    }
}

extension Internals.PrivateKey {

    func build() throws -> NIOSSLPrivateKey {
        let format = format.build()

        switch source {
        case .bytes(let bytes):
            if let password {
                return try .init(bytes: bytes, format: format) {
                    $0(Array(password))
                }
            } else {
                return try .init(bytes: bytes, format: format)
            }
        case .file(let file):
            if let password {
                return try .init(file: file, format: format) {
                    $0(Array(password))
                }
            } else {
                return try .init(file: file, format: format)
            }
        }
    }
}
