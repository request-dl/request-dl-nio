/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public struct PrivateKey<Password: Collection> where Password.Element == UInt8 {

    public typealias PasswordClosure = ((Password) -> Void) throws -> Void

    enum Source {
        case file(String)
        case bytes([UInt8])
    }

    let source: Source
    let format: CertificateFormat
    let password: PasswordClosure?

    public init(_ file: String, format: CertificateFormat) where Password == [UInt8] {
        self.source = .file(file)
        self.format = format
        self.password = nil
    }

    public init(_ bytes: [UInt8], format: CertificateFormat) where Password == [UInt8] {
        self.source = .bytes(bytes)
        self.format = format
        self.password = nil
    }

    public init(_ file: String, format: CertificateFormat, password: @escaping PasswordClosure) {
        self.source = .file(file)
        self.format = format
        self.password = password
    }

    public init(_ bytes: [UInt8], format: CertificateFormat, password: @escaping PasswordClosure) {
        self.source = .bytes(bytes)
        self.format = format
        self.password = password
    }
}

extension PrivateKey: PrivateKeyRepresentable {

    public func build() throws -> NIOSSLPrivateKey {
        let format = format.build()

        switch source {
        case .bytes(let bytes):
            if let password {
                return try .init(bytes: bytes, format: format, passphraseCallback: password)
            } else {
                return try .init(bytes: bytes, format: format)
            }
        case .file(let file):
            if let password {
                return try .init(file: file, format: format, passphraseCallback: password)
            } else {
                return try .init(file: file, format: format)
            }
        }
    }
}
