/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOSSL

public struct CertificatePrivateKey<Password: CertificatePasswordProvider> {

    enum Source {
        case file(String)
        case bytes([UInt8])
    }

    let source: Source
    let format: CertificateFormat
    let password: () -> Password

    public init(_ file: String, format: CertificateFormat) where Password == CertificateEmptyPassword {
        self.source = .file(file)
        self.format = format
        self.password = { CertificateEmptyPassword() }
    }

    public init(_ bytes: [UInt8], format: CertificateFormat) where Password == CertificateEmptyPassword  {
        self.source = .bytes(bytes)
        self.format = format
        self.password = { CertificateEmptyPassword() }
    }

    public init(_ file: String, format: CertificateFormat, password: @escaping () -> Password) {
        self.source = .file(file)
        self.format = format
        self.password = password
    }

    public init(_ bytes: [UInt8], format: CertificateFormat, password: @escaping () -> Password) {
        self.source = .bytes(bytes)
        self.format = format
        self.password = password
    }
}

extension CertificatePrivateKey: CertificatePrivateKeyRepresentable {

    public func build() throws -> NIOSSLPrivateKey {
        let format = format.build()

        switch source {
        case .bytes(let bytes):
            if Password.self is CertificateEmptyPassword.Type {
                return try .init(bytes: bytes, format: format)
            } else {
                return try .init(bytes: bytes, format: format) {
                    $0(password().callAsFunction())
                }
            }
        case .file(let file):
            if Password.self is CertificateEmptyPassword.Type {
                return try .init(file: file, format: format)
            } else {
                return try .init(file: file, format: format) {
                    $0(password().callAsFunction())
                }
            }
        }
    }
}
